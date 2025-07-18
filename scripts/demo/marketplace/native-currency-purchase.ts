/**
 * СЦЕНАРИЙ 1: Покупка товара в нативной валюте (ETH)
 * 
 * Демонстрирует базовую функциональность маркетплейса - покупку товара
 * за нативную валюту блокчейна (ETH) с полным анализом комиссий.
 * 
 * ОСНОВНЫЕ ЭТАПЫ:
 * 1. Подготовка участников и проверка начальных балансов
 * 2. Создание товара и листинга с подписью продавца
 * 3. Проверка достаточности средств у покупателя
 * 4. Выполнение покупки через смарт-контракт
 * 5. Анализ комиссий и изменений балансов
 * 6. Верификация корректности транзакции
 * 
 * ОЖИДАЕМЫЕ РЕЗУЛЬТАТЫ:
 * - Покупатель: баланс ETH уменьшился на сумму покупки + комиссии
 * - Продавец: баланс ETH увеличился на сумму покупки - комиссии маркетплейса
 * - Gateway: баланс ETH увеличился на сумму комиссий
 * - Транзакция выполнена успешно без ошибок
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
 * Сценарий покупки в нативной валюте (ETH)
 */
export class NativeCurrencyPurchaseScenario extends BaseScenario {

    constructor(
        deployment: DeploymentResult,
        seller: Signer,
        buyer: Signer
    ) {
        const product: Product = {
            id: 1001,
            price: ethers.parseEther("0.05"), // 0.05 ETH - доступная цена для тестирования
            tokenAddress: ethers.ZeroAddress, // Нативная валюта (ETH)
            discount: 0
        };

        const config: ScenarioConfig = {
            name: "СЦЕНАРИЙ 1: Покупка в нативной валюте (ETH)",
            description: "Тестирование базовой покупки товара за ETH с полным анализом комиссий",
            product: product,
            prepareTokens: false // Не нужно подготавливать токены для ETH
        };

        super(deployment, seller, buyer, config);
    }

    /**
     * Анализ комиссий для ETH транзакций
     *
     * Переопределяет базовый метод, добавляя специфический анализ
     * для транзакций в нативной валюте.
     */
    protected analyzeCommissions(
        sellerChanges: BalanceChange,
        buyerChanges: BalanceChange,
        gatewayChanges: BalanceChange,
        listingPrice: bigint
    ): void {
        // Вызов базовой реализации
        super.analyzeCommissions(sellerChanges, buyerChanges, gatewayChanges, listingPrice);

        console.log("\n🔍 Дополнительный анализ ETH транзакции:");

        // Проверяем корректность базовых расчетов
        const totalPaid = -buyerChanges.nativeChange;
        const sellerReceived = sellerChanges.nativeChange;
        const gatewayReceived = gatewayChanges.nativeChange;

        console.log(`  Цена товара по листингу: ${ethers.formatEther(listingPrice)} ETH`);
        console.log(`  Фактически заплачено покупателем: ${ethers.formatEther(totalPaid)} ETH`);
        console.log(`  Разница (комиссии + газ): ${ethers.formatEther(totalPaid - listingPrice)} ETH`);

        // Проверяем баланс средств
        const totalReceived = sellerReceived + gatewayReceived;
        console.log(`  Общая сумма получена (продавец + gateway): ${ethers.formatEther(totalReceived)} ETH`);

        // Анализируем эффективность для участников
        const sellerEfficiency = (sellerReceived * 100n) / listingPrice;
        console.log(`  Эффективность для продавца: ${sellerEfficiency}% от цены товара`);

        // Проверяем разумность комиссий
        const totalFees = totalPaid - sellerReceived;
        const feePercentage = (totalFees * 10000n) / listingPrice; // В базисных пунктах
        console.log(`  Общие комиссии: ${ethers.formatEther(totalFees)} ETH (${feePercentage} bp)`);

        if (feePercentage > 1000n) { // Более 10%
            console.log("  ⚠️ ВНИМАНИЕ: Комиссии превышают 10% от стоимости товара");
        } else {
            console.log("  ✅ Комиссии находятся в разумных пределах");
        }
    }
}

/**
 * Функция-обертка для запуска сценария (для обратной совместимости)
 */
export async function testNativeCurrencyPurchase(
    deployment: DeploymentResult,
    seller: Signer,
    buyer: Signer
): Promise<ScenarioResult> {
    const scenario = new NativeCurrencyPurchaseScenario(deployment, seller, buyer);
    return await scenario.execute();
}
