/**
 * СЦЕНАРИЙ 3: Покупка товара со скидкой
 * 
 * Демонстрирует покупку товара со скидкой, включая расчет финальной цены
 * и корректное распределение комиссий с учетом скидочной цены.
 * 
 * ОСНОВНЫЕ ЭТАПЫ:
 * 1. Подготовка участников и проверка начальных балансов
 * 2. Создание товара с оригинальной ценой и размером скидки
 * 3. Расчет финальной цены со скидкой
 * 4. Создание скидочного листинга с подписью продавца
 * 5. Проверка достаточности средств по скидочной цене
 * 6. Выполнение покупки по сниженной цене
 * 7. Анализ комиссий от скидочной цены
 * 8. Анализ экономии покупателя и влияния на участников
 * 9. Верификация корректности скидочной системы
 * 
 * ОЖИДАЕМЫЕ РЕЗУЛЬТАТЫ:
 * - Покупатель: заплатил скидочную цену (экономия 20%)
 * - Продавец: получил скидочную цену за вычетом комиссий
 * - Gateway: получил комиссию от скидочной цены
 * - Комиссии рассчитываются от финальной (скидочной) цены
 */

import { ethers } from "hardhat";
import { Signer } from "ethers";
import { DeploymentResult } from "../utils/deploy";
import { Product, createDiscountedListing } from "../utils/marketplace";
import { BaseScenario, ScenarioConfig, ScenarioResult } from "./base-scenario";
import { BalanceChange } from "../utils/balance";

/**
 * Сценарий покупки со скидкой
 */
export class DiscountPurchaseScenario extends BaseScenario {
    private originalPrice: bigint;
    private discountPercent: number;

    constructor(
        deployment: DeploymentResult,
        seller: Signer,
        buyer: Signer
    ) {
        // Параметры скидки
        const originalPrice = ethers.parseEther("0.1"); // 0.1 ETH оригинальная цена
        const discountPercent = 2000; // 20% скидка (в базисных пунктах)

        // Рассчитываем финальную цену со скидкой
        const discountAmount = (originalPrice * BigInt(discountPercent)) / 10000n;
        const finalPrice = originalPrice - discountAmount;

        const product: Product = {
            id: 1003,
            price: finalPrice, // Финальная цена со скидкой
            tokenAddress: ethers.ZeroAddress, // Нативная валюта (ETH)
            discount: discountPercent
        };

        const config: ScenarioConfig = {
            name: "СЦЕНАРИЙ 3: Покупка со скидкой",
            description: "Тестирование покупки товара со скидкой и анализ влияния скидки на комиссии",
            product: product,
            prepareTokens: false
        };

        super(deployment, seller, buyer, config);

        this.originalPrice = originalPrice;
        this.discountPercent = discountPercent;
    }

    /**
     * Переопределяем создание листинга для использования скидочной функции
     */
    protected async createListing(): Promise<{ listing: any; signature: string }> {
        console.log("\n🏷️ Создание скидочного листинга:");
        console.log(`  Оригинальная цена: ${ethers.formatEther(this.originalPrice)} ETH`);
        console.log(`  Размер скидки: ${this.discountPercent / 100}%`);
        console.log(`  Финальная цена: ${ethers.formatEther(this.config.product.price)} ETH`);

        return await createDiscountedListing(
            this.deployment.marketplace,
            this.seller,
            this.config.product.id,
            this.originalPrice,
            this.discountPercent,
            this.config.product.tokenAddress
        );
    }

    /**
     * Дополнительный анализ для скидочных транзакций
     * 
     * Выполняет специфический анализ для транзакций со скидкой,
     * включая анализ экономии, влияния на участников и разумности скидки.
     */
    protected async performAdditionalAnalysis(
        listing: any,
        sellerChanges: BalanceChange,
        buyerChanges: BalanceChange,
        gatewayChanges: BalanceChange
    ): Promise<void> {
        console.log("\n🔍 Дополнительный анализ скидочной транзакции:");

        // Основные суммы
        const totalPaid = -buyerChanges.nativeChange;
        const sellerReceived = sellerChanges.nativeChange;
        const gatewayReceived = gatewayChanges.nativeChange;

        // Анализ скидки
        const discountAmount = this.originalPrice - listing.price;
        const actualSavings = this.originalPrice - totalPaid;

        console.log("\n🎯 Анализ скидки:");
        console.log(`  Оригинальная цена: ${ethers.formatEther(this.originalPrice)} ETH`);
        console.log(`  Цена со скидкой: ${ethers.formatEther(listing.price)} ETH`);
        console.log(`  Размер скидки: ${this.discountPercent / 100}%`);
        console.log(`  Теоретическая экономия: ${ethers.formatEther(discountAmount)} ETH`);
        console.log(`  Фактическая экономия: ${ethers.formatEther(actualSavings)} ETH`);

        // Проверяем корректность скидки
        if (discountAmount === actualSavings) {
            console.log("  ✅ Скидка применена корректно");
        } else {
            const difference = actualSavings - discountAmount;
            console.log(`  ⚠️ Разница в экономии: ${ethers.formatEther(difference)} ETH`);
        }

        // Анализ влияния скидки на участников
        console.log("\n💰 Влияние скидки на участников:");

        // Для покупателя
        const buyerSavingsPercent = (actualSavings * 100n) / this.originalPrice;
        console.log(`  Покупатель сэкономил: ${buyerSavingsPercent}% от оригинальной цены`);

        // Для продавца
        const sellerLossFromDiscount = discountAmount;
        const sellerLossFromFees = listing.price - sellerReceived;
        const totalSellerLoss = sellerLossFromDiscount + sellerLossFromFees;

        console.log(`  Продавец потерял от скидки: ${ethers.formatEther(sellerLossFromDiscount)} ETH`);
        console.log(`  Продавец потерял от комиссий: ${ethers.formatEther(sellerLossFromFees)} ETH`);
        console.log(`  Общие потери продавца: ${ethers.formatEther(totalSellerLoss)} ETH`);

        const sellerEfficiencyFromOriginal = (sellerReceived * 100n) / this.originalPrice;
        console.log(`  Эффективность продавца от оригинальной цены: ${sellerEfficiencyFromOriginal}%`);

        // Для gateway
        const gatewayFeesFromDiscounted = gatewayReceived;
        const theoreticalFeesFromOriginal = this.estimateFeesFromPrice(this.originalPrice);

        console.log(`  Gateway получил комиссий: ${ethers.formatEther(gatewayFeesFromDiscounted)} ETH`);
        console.log(`  Теоретические комиссии с полной цены: ${ethers.formatEther(theoreticalFeesFromOriginal)} ETH`);

        const gatewayLossFromDiscount = theoreticalFeesFromOriginal - gatewayFeesFromDiscounted;
        console.log(`  Gateway потерял от скидки: ${ethers.formatEther(gatewayLossFromDiscount)} ETH`);

        // Проверяем баланс экономики
        console.log("\n⚖️ Баланс экономики скидки:");
        const totalSystemLoss = sellerLossFromDiscount + gatewayLossFromDiscount;
        console.log(`  Общие потери системы: ${ethers.formatEther(totalSystemLoss)} ETH`);
        console.log(`  Выгода покупателя: ${ethers.formatEther(actualSavings)} ETH`);

        if (totalSystemLoss === actualSavings) {
            console.log("  ✅ Экономический баланс скидки корректен");
        } else {
            const imbalance = actualSavings - totalSystemLoss;
            console.log(`  ⚠️ Дисбаланс в экономике: ${ethers.formatEther(imbalance)} ETH`);
        }

        // Анализ разумности скидки
        this.analyzeDiscountReasonableness(listing, sellerReceived, gatewayReceived);
    }

    /**
     * Оценка комиссий от заданной цены (упрощенная)
     */
    private estimateFeesFromPrice(price: bigint): bigint {
        // Примерная оценка комиссий (обычно 2-5% от цены)
        // Это упрощенная оценка для демонстрации
        return (price * 300n) / 10000n; // 3% комиссия
    }

    /**
     * Анализ разумности скидки
     */
    private analyzeDiscountReasonableness(
        listing: any,
        sellerReceived: bigint,
        gatewayReceived: bigint
    ): void {
        console.log("\n🧮 Анализ разумности скидки:");

        const discountPercent = this.discountPercent / 100;

        // Проверяем размер скидки
        if (discountPercent > 50) {
            console.log("  ⚠️ ВНИМАНИЕ: Скидка превышает 50% - очень высокая");
        } else if (discountPercent > 30) {
            console.log("  ⚠️ Скидка довольно высокая (>30%)");
        } else if (discountPercent > 10) {
            console.log("  ✅ Скидка умеренная (10-30%)");
        } else {
            console.log("  ✅ Скидка небольшая (<10%)");
        }

        // Проверяем влияние на продавца
        const sellerRetentionPercent = (sellerReceived * 100n) / this.originalPrice;
        console.log(`  Продавец сохраняет: ${sellerRetentionPercent}% от оригинальной цены`);

        if (sellerRetentionPercent < 50n) {
            console.log("  ⚠️ ВНИМАНИЕ: Продавец получает менее 50% от оригинальной цены");
        } else if (sellerRetentionPercent < 70n) {
            console.log("  ⚠️ Продавец получает менее 70% от оригинальной цены");
        } else {
            console.log("  ✅ Продавец получает разумную долю от оригинальной цены");
        }

        // Проверяем влияние на комиссии
        const feeRetentionPercent = (gatewayReceived * 100n) / this.estimateFeesFromPrice(this.originalPrice);
        console.log(`  Gateway сохраняет: ${feeRetentionPercent}% от потенциальных комиссий`);

        if (feeRetentionPercent < 50n) {
            console.log("  ⚠️ Значительное снижение комиссий из-за скидки");
        } else {
            console.log("  ✅ Комиссии сохраняются на разумном уровне");
        }
    }
}

/**
 * Функция-обертка для запуска сценария (для обратной совместимости)
 */
export async function testDiscountPurchase(
    deployment: DeploymentResult,
    seller: Signer,
    buyer: Signer
): Promise<ScenarioResult> {
    const scenario = new DiscountPurchaseScenario(deployment, seller, buyer);
    return await scenario.execute();
}
