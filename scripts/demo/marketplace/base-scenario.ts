/**
 * Базовый класс для сценариев маркетплейса
 *
 * Содержит общую логику для всех сценариев тестирования маркетплейса,
 * устраняя дублирование кода и обеспечивая единообразный подход к тестированию.
 */

import {ethers} from "hardhat";
import {Signer, TransactionReceipt} from "ethers";
import {DeploymentResult} from "../utils/deploy";
import {createListing, purchaseListing, Product} from "../utils/marketplace";
import {
    getAccountBalances,
    displayBalances,
    calculateBalanceChanges,
    displayBalanceChanges,
    analyzeFees,
    prepareTokensForTesting,
    checkSufficientBalance,
    BalanceInfo,
    BalanceChange
} from "../utils/balance";

/**
 * Результат выполнения сценария тестирования
 */
export interface ScenarioResult {
    name: string;
    success: boolean;
    details: ScenarioDetails;
    error?: string;
}

/**
 * Детальная информация о результатах сценария
 */
export interface ScenarioDetails {
    productPrice: string;
    currency: string;
    sellerEarned: string;
    buyerSpent: string;
    gatewayEarned: string;
    fees: any;
    transactionHash?: string;
    gasUsed?: string;
}

/**
 * Конфигурация для сценария тестирования
 */
export interface ScenarioConfig {
    name: string;
    description: string;
    product: Product;
    tokenSymbols?: Map<string, string>;
    prepareTokens?: boolean;
    tokenAmount?: bigint;
}

/**
 * Структура листинга с подписью
 */
export interface ListingWithSignature {
    listing: any;
    signature: string;
}

/**
 * Базовый класс для сценариев маркетплейса
 * Устраняет дублирование кода между сценариями
 */
export abstract class BaseScenario {
    protected deployment: DeploymentResult;
    protected seller: Signer;
    protected buyer: Signer;
    protected config: ScenarioConfig;

    constructor(
        deployment: DeploymentResult,
        seller: Signer,
        buyer: Signer,
        config: ScenarioConfig
    ) {
        this.deployment = deployment;
        this.seller = seller;
        this.buyer = buyer;
        this.config = config;
    }

    /**
     * Выполняет сценарий тестирования с общей логикой
     *
     * @returns Результат выполнения сценария с детальной информацией
     */
    async execute(): Promise<ScenarioResult> {
        console.log(`\n🧪 ${this.config.name}`);
        console.log("=".repeat(50));
        console.log(`📝 ${this.config.description}`);

        try {
            // Шаг 1: Подготовка участников
            const sellerAddress = await this.seller.getAddress();
            const buyerAddress = await this.buyer.getAddress();

            console.log("\n👥 Участники:");
            console.log(`  Продавец: ${sellerAddress}`);
            console.log(`  Покупатель: ${buyerAddress}`);

            // Шаг 2: Подготовка токенов (если необходимо)
            if (this.config.prepareTokens && this.config.tokenAmount) {
                await this.prepareTokens();
            }

            // Шаг 3: Получение начальных балансов
            const tokenAddresses = this.getTokenAddresses();
            const sellerBalanceBefore = await getAccountBalances(sellerAddress, tokenAddresses);
            const buyerBalanceBefore = await getAccountBalances(buyerAddress, tokenAddresses);
            const gatewayBalanceBefore = await getAccountBalances(await this.deployment.gateway.getAddress(), tokenAddresses);

            console.log("\n💰 Начальные балансы:");
            await displayBalances(sellerBalanceBefore, this.config.tokenSymbols);
            await displayBalances(buyerBalanceBefore, this.config.tokenSymbols);

            // Шаг 4: Создание листинга (может быть переопределено в наследниках)
            const {listing, signature} = await this.createListing();

            // Шаг 5: Проверка достаточности средств
            const sufficient = await checkSufficientBalance(
                buyerAddress,
                this.config.product.tokenAddress,
                listing.price
            );

            if (!sufficient) {
                throw new Error("Недостаточно средств у покупателя");
            }

            console.log("\n🛒 Выполнение покупки...");

            // Шаг 6: Покупка товара
            const receipt = await purchaseListing(
                this.deployment.marketplace,
                this.buyer,
                listing,
                signature,
                this.config.product.tokenAddress,
                this.deployment.gateway
            );

            // Шаг 7: Анализ комиссий (интегрировано в каждый сценарий)
            const fees = await analyzeFees(receipt, this.deployment.marketplace);

            // Шаг 8: Получение финальных балансов
            const sellerBalanceAfter = await getAccountBalances(sellerAddress, tokenAddresses);
            const buyerBalanceAfter = await getAccountBalances(buyerAddress, tokenAddresses);
            const gatewayBalanceAfter = await getAccountBalances(await this.deployment.gateway.getAddress(), tokenAddresses);

            console.log("\n💰 Финальные балансы:");
            await displayBalances(sellerBalanceAfter, this.config.tokenSymbols);
            await displayBalances(buyerBalanceAfter, this.config.tokenSymbols);

            // Шаг 9: Анализ изменений балансов
            const sellerChanges = calculateBalanceChanges(sellerBalanceBefore, sellerBalanceAfter);
            const buyerChanges = calculateBalanceChanges(buyerBalanceBefore, buyerBalanceAfter);
            const gatewayChanges = calculateBalanceChanges(gatewayBalanceBefore, gatewayBalanceAfter);

            console.log("\n📊 Изменения балансов:");
            console.log("Продавец:");
            displayBalanceChanges(sellerChanges, this.config.tokenSymbols);
            console.log("Покупатель:");
            displayBalanceChanges(buyerChanges, this.config.tokenSymbols);

            // Шаг 10: Анализ комиссий
            this.analyzeCommissions(sellerChanges, buyerChanges, gatewayChanges, listing.price);

            console.log(`\n✅ ${this.config.name} выполнен успешно!`);

            return {
                name: this.config.name,
                success: true,
                details: this.buildResultDetails(listing, sellerChanges, buyerChanges, gatewayChanges, fees, receipt),
                error: undefined
            };

        } catch (error) {
            console.log(`❌ Ошибка в сценарии: ${error}`);
            return {
                name: this.config.name,
                success: false,
                details: {
                    productPrice: "0",
                    currency: "N/A",
                    sellerEarned: "0",
                    buyerSpent: "0",
                    gatewayEarned: "0",
                    fees: null
                },
                error: error instanceof Error ? error.message : String(error)
            };
        }
    }

    /**
     * Подготовка токенов для тестирования (если необходимо)
     */
    protected async prepareTokens(): Promise<void> {
        if (!this.config.tokenAmount) return;

        console.log("\n🪙 Подготовка токенов для покупателя...");
        await prepareTokensForTesting(
            this.deployment.testToken,
            this.buyer,
            await this.deployment.marketplace.getAddress(),
            this.config.tokenAmount
        );
    }

    /**
     * Получение списка адресов токенов для отслеживания балансов
     */
    protected getTokenAddresses(): string[] {
        const addresses: string[] = [];
        if (this.config.product.tokenAddress !== ethers.ZeroAddress) {
            addresses.push(this.config.product.tokenAddress);
        }
        return addresses;
    }

    /**
     * Создание листинга (может быть переопределено в наследниках)
     *
     * @returns Листинг с подписью продавца
     */
    protected async createListing(): Promise<ListingWithSignature> {
        return await createListing(this.deployment.marketplace, this.seller, this.config.product);
    }

    /**
     * Анализ комиссий (интегрирован в каждый сценарий)
     *
     * @param sellerChanges Изменения баланса продавца
     * @param buyerChanges Изменения баланса покупателя
     * @param gatewayChanges Изменения баланса gateway
     * @param listingPrice Цена товара в листинге
     */
    protected analyzeCommissions(
        sellerChanges: BalanceChange,
        buyerChanges: BalanceChange,
        gatewayChanges: BalanceChange,
        listingPrice: bigint
    ): void {
        console.log("\n💸 Анализ комиссий:");

        const isNative = this.config.product.tokenAddress === ethers.ZeroAddress;

        if (isNative) {
            const totalPaid = -buyerChanges.nativeChange;
            const sellerReceived = sellerChanges.nativeChange;
            const gatewayReceived = gatewayChanges.nativeChange;
            const estimatedFees = totalPaid - sellerReceived;

            console.log(`  Покупатель заплатил: ${ethers.formatEther(totalPaid)} ETH`);
            console.log(`  Продавец получил: ${ethers.formatEther(sellerReceived)} ETH`);
            console.log(`  Gateway получил: ${ethers.formatEther(gatewayReceived)} ETH`);
            console.log(`  Расчетные комиссии: ${ethers.formatEther(estimatedFees)} ETH`);
            console.log(`  Цена товара: ${ethers.formatEther(listingPrice)} ETH`);
        } else {
            const tokenAddress = this.config.product.tokenAddress;
            const totalPaid = -(buyerChanges.tokenChanges.get(tokenAddress) || 0n);
            const sellerReceived = sellerChanges.tokenChanges.get(tokenAddress) || 0n;
            const gatewayReceived = gatewayChanges.tokenChanges.get(tokenAddress) || 0n;
            const estimatedFees = totalPaid - sellerReceived;

            const symbol = this.config.tokenSymbols?.get(tokenAddress) || "TOKEN";
            console.log(`  Покупатель заплатил: ${ethers.formatEther(totalPaid)} ${symbol}`);
            console.log(`  Продавец получил: ${ethers.formatEther(sellerReceived)} ${symbol}`);
            console.log(`  Gateway получил: ${ethers.formatEther(gatewayReceived)} ${symbol}`);
            console.log(`  Расчетные комиссии: ${ethers.formatEther(estimatedFees)} ${symbol}`);
            console.log(`  Цена товара: ${ethers.formatEther(listingPrice)} ${symbol}`);
        }
    }


    /**
     * Построение детальных результатов сценария
     *
     * @param listing Информация о листинге
     * @param sellerChanges Изменения баланса продавца
     * @param buyerChanges Изменения баланса покупателя
     * @param gatewayChanges Изменения баланса gateway
     * @param fees Информация о комиссиях
     * @param receipt Квитанция транзакции
     * @returns Детальная информация о результатах
     */
    protected buildResultDetails(
        listing: any,
        sellerChanges: BalanceChange,
        buyerChanges: BalanceChange,
        gatewayChanges: BalanceChange,
        fees: any,
        receipt: TransactionReceipt | null
    ): ScenarioDetails {
        const isNative = this.config.product.tokenAddress === ethers.ZeroAddress;

        if (isNative) {
            return {
                productPrice: ethers.formatEther(listing.price),
                currency: "ETH",
                sellerEarned: ethers.formatEther(sellerChanges.nativeChange),
                buyerSpent: ethers.formatEther(-buyerChanges.nativeChange),
                gatewayEarned: ethers.formatEther(gatewayChanges.nativeChange),
                fees: fees,
                transactionHash: receipt?.hash
            };
        } else {
            const tokenAddress = this.config.product.tokenAddress;
            const symbol = this.config.tokenSymbols?.get(tokenAddress) || "TOKEN";

            return {
                productPrice: ethers.formatEther(listing.price),
                currency: symbol,
                sellerEarned: ethers.formatEther(sellerChanges.tokenChanges.get(tokenAddress) || 0n),
                buyerSpent: ethers.formatEther(-(buyerChanges.tokenChanges.get(tokenAddress) || 0n)),
                gatewayEarned: ethers.formatEther(gatewayChanges.tokenChanges.get(tokenAddress) || 0n),
                fees: fees,
                transactionHash: receipt?.hash
            };
        }
    }
}
