/**
 * СЦЕНАРИЙ 2: Покупка товара в токене (ERC20)
 * 
 * Демонстрирует покупку товара за ERC20 токены, включая подготовку токенов,
 * выдачу разрешений (approve) и обработку комиссий в токенах.
 * 
 * ОСНОВНЫЕ ЭТАПЫ:
 * 1. Подготовка участников и получение адреса токена
 * 2. Минт тестовых токенов покупателю и выдача разрешений
 * 3. Проверка начальных балансов токенов
 * 4. Создание товара и листинга с ценой в токенах
 * 5. Проверка достаточности токенов и разрешений
 * 6. Выполнение покупки с переводом токенов
 * 7. Анализ комиссий и изменений балансов в токенах
 * 8. Верификация корректности транзакции
 * 
 * ОЖИДАЕМЫЕ РЕЗУЛЬТАТЫ:
 * - Покупатель: баланс токенов уменьшился на сумму покупки
 * - Продавец: баланс токенов увеличился на сумму покупки - комиссии
 * - Gateway: баланс токенов увеличился на сумму комиссий
 * - ETH балансы изменились только на стоимость газа
 */

import { ethers } from "hardhat";
import { Signer } from "ethers";
import { DeploymentResult } from "../utils/deploy";
import { Product } from "../utils/marketplace";
import { BaseScenario, ScenarioConfig, ScenarioResult } from "./base-scenario";
import { 
    BalanceChange, 
    BalanceInfo, 
    getAccountBalances, 
    calculateBalanceChanges 
} from "../utils/balance";

/**
 * Сценарий покупки в токене (ERC20)
 */
export class TokenPurchaseScenario extends BaseScenario {

    private constructor(
        deployment: DeploymentResult,
        seller: Signer,
        buyer: Signer,
        config: ScenarioConfig
    ) {
        super(deployment, seller, buyer, config);
    }

    /**
     * Статический метод для создания сценария с асинхронной инициализацией
     */
    static async create(
        deployment: DeploymentResult,
        seller: Signer,
        buyer: Signer
    ): Promise<TokenPurchaseScenario> {
        const tokenAddress = await deployment.testToken.getAddress();

        const product: Product = {
            id: 1002,
            price: ethers.parseEther("10"), // 10 DEMO токенов
            tokenAddress: tokenAddress,
            discount: 0
        };

        const tokenSymbols = new Map([
            [tokenAddress, "DEMO"]
        ]);

        const config: ScenarioConfig = {
            name: "СЦЕНАРИЙ 2: Покупка в токене (ERC20)",
            description: "Тестирование покупки товара за ERC20 токены с анализом комиссий в токенах",
            product: product,
            tokenSymbols: tokenSymbols,
            prepareTokens: true,
            tokenAmount: ethers.parseEther("100") // 100 DEMO токенов для покупателя
        };

        return new TokenPurchaseScenario(deployment, seller, buyer, config);
    }

    /**
     * Анализ комиссий для транзакций с токенами
     *
     * Переопределяет базовый метод, добавляя специфический анализ
     * для транзакций с ERC20 токенами.
     */
    protected analyzeCommissions(
        sellerChanges: BalanceChange,
        buyerChanges: BalanceChange,
        gatewayChanges: BalanceChange,
        listingPrice: bigint
    ): void {
        // Вызов базовой реализации
        super.analyzeCommissions(sellerChanges, buyerChanges, gatewayChanges, listingPrice);

        console.log("\n🔍 Дополнительный анализ транзакции в токенах:");

        const tokenAddress = this.config.product.tokenAddress;
        const symbol = this.config.tokenSymbols?.get(tokenAddress) || "TOKEN";

        // Получаем изменения в токенах
        const totalPaid = -(buyerChanges.tokenChanges.get(tokenAddress) || 0n);
        const sellerReceived = sellerChanges.tokenChanges.get(tokenAddress) || 0n;
        const gatewayReceived = gatewayChanges.tokenChanges.get(tokenAddress) || 0n;

        console.log(`  Цена товара по листингу: ${ethers.formatEther(listingPrice)} ${symbol}`);
        console.log(`  Фактически заплачено покупателем: ${ethers.formatEther(totalPaid)} ${symbol}`);

        // Проверяем точность переводов в токенах
        if (totalPaid === listingPrice) {
            console.log("  ✅ Покупатель заплатил точную сумму по листингу");
        } else {
            console.log(`  ⚠️ Разница в оплате: ${ethers.formatEther(totalPaid - listingPrice)} ${symbol}`);
        }

        // Проверяем баланс токенов
        const totalReceived = sellerReceived + gatewayReceived;
        console.log(`  Общая сумма получена (продавец + gateway): ${ethers.formatEther(totalReceived)} ${symbol}`);

        // Проверяем сохранение токенов (не должно быть потерь)
        if (totalPaid === totalReceived) {
            console.log("  ✅ Все токены корректно распределены, потерь нет");
        } else {
            const difference = totalPaid - totalReceived;
            console.log(`  ⚠️ ВНИМАНИЕ: Обнаружена разница в ${ethers.formatEther(difference)} ${symbol}`);
        }

        // Анализируем эффективность для продавца
        const sellerEfficiency = (sellerReceived * 100n) / listingPrice;
        console.log(`  Эффективность для продавца: ${sellerEfficiency}% от цены товара`);

        // Проверяем комиссии в токенах
        const tokenFees = totalPaid - sellerReceived;
        const feePercentage = (tokenFees * 10000n) / listingPrice; // В базисных пунктах
        console.log(`  Комиссии в токенах: ${ethers.formatEther(tokenFees)} ${symbol} (${feePercentage} bp)`);

        // Проверяем влияние на ETH балансы (должно быть только газ)
        console.log("\n💨 Анализ расходов на газ:");
        console.log(`  Продавец потратил на газ: ${ethers.formatEther(-sellerChanges.nativeChange)} ETH`);
        console.log(`  Покупатель потратил на газ: ${ethers.formatEther(-buyerChanges.nativeChange)} ETH`);

        // Проверяем разрешения токенов
        this.checkTokenAllowances().catch(error => {
            console.log(`  ❌ Ошибка при проверке разрешений: ${error}`);
        });
    }

    /**
     * Проверка разрешений токенов после транзакции
     */
    private async checkTokenAllowances(): Promise<void> {
        console.log("\n🔐 Проверка разрешений токенов:");

        const buyerAddress = await this.buyer.getAddress();
        const marketplaceAddress = await this.deployment.marketplace.getAddress();

        try {
            const allowance = await this.deployment.testToken.allowance(buyerAddress, marketplaceAddress);
            console.log(`  Оставшееся разрешение покупателя: ${ethers.formatEther(allowance)} DEMO`);

            const buyerBalance = await this.deployment.testToken.balanceOf(buyerAddress);
            console.log(`  Оставшийся баланс покупателя: ${ethers.formatEther(buyerBalance)} DEMO`);

            if (allowance > buyerBalance) {
                console.log("  ✅ Разрешение превышает баланс - это нормально");
            } else if (allowance === 0n) {
                console.log("  ⚠️ Разрешение полностью использовано");
            } else {
                console.log("  ✅ Разрешение и баланс в порядке");
            }
        } catch (error) {
            console.log(`  ❌ Ошибка при проверке разрешений: ${error}`);
        }
    }
}

/**
 * Функция-обертка для запуска сценария (для обратной совместимости)
 */
export async function testTokenPurchase(
    deployment: DeploymentResult,
    seller: Signer,
    buyer: Signer
): Promise<ScenarioResult> {
    const scenario = await TokenPurchaseScenario.create(deployment, seller, buyer);
    return await scenario.execute();
}
