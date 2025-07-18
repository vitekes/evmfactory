import { ethers } from "hardhat";
import { Signer, TransactionReceipt } from "ethers";
import { DeploymentResult } from "../utils/deploy";
import {
    getAccountBalances,
    getMultipleAccountBalances,
    displayBalances,
    displayMultipleBalances,
    calculateBalanceChanges,
    calculateMultipleBalanceChanges,
    displayBalanceChanges,
    displayMultipleBalanceChanges,
    analyzeFees,
    prepareTokensForTesting,
    checkSufficientBalance,
    BalanceInfo,
    BalanceChange
} from "../utils/balance";

// Типы для результатов сценариев
export class ScenarioResult {
    constructor(
        public name: string,
        public success: boolean,
        public error?: string,
        public details?: ScenarioDetails
    ) {}
}

export class ScenarioDetails {
    constructor(
        public contestId: string,
        public prizeCount: number,
        public totalPrizeValue: string,
        public currency: string,
        public creatorSpent: string,
        public winnersReceived: string,
        public gatewayEarned: string,
        public gasUsed: string
    ) {}
}

export class ScenarioConfig {
    constructor(
        public contestName: string,
        public description: string,
        public expectedOutcome: string
    ) {}
}

export interface ContestPrize {
    prizeType: number; // 0 = MONETARY, 1 = PROMO
    token: string;
    amount: string;
    distribution: number; // 0 = flat, 1 = descending
    uri: string;
}

export interface ContestDeployment {
    contestFactory: any;
    paymentGateway: any;
    testToken: any;
    core: any;
}

// Type definitions for parsed log events
export interface ParsedLogResult {
    name: string;
    args: any;
}

export interface ContestCreatedEventArgs {
    contestId: string;
    creator: string;
    escrow: string;
}

export interface MonetaryPrizePaidEventArgs {
    to: string;
    amount: string;
    slot: number;
}

export interface PromoPrizeIssuedEventArgs {
    to: string;
    slot: number;
    uri: string;
}

// Type definitions for method parameters
export interface ContestResult {
    escrowAddress: string;
    contestId: string;
    totalPrizeValue: string;
    receipt: any;
}

export interface FinalizeResult {
    winners: string[];
    receipt: any;
}

export class BaseScenario {
    protected deployment: DeploymentResult;
    protected creator: Signer;
    protected participants: Signer[];
    protected config: ScenarioConfig;

    constructor(
        deployment: DeploymentResult,
        creator: Signer,
        participants: Signer[],
        config: ScenarioConfig
    ) {
        this.deployment = deployment;
        this.creator = creator;
        this.participants = participants;
        this.config = config;
    }

    async execute(): Promise<ScenarioResult> {
        console.log(`\n🎯 СЦЕНАРИЙ: ${this.config.contestName}`);
        console.log("=".repeat(60));
        console.log(`📝 Описание: ${this.config.description}`);
        console.log(`🎯 Ожидаемый результат: ${this.config.expectedOutcome}`);
        console.log("=".repeat(60));

        try {
            // 0. Настройка ролей для создания конкурсов
            console.log("🔐 Настройка ролей для создания конкурсов...");
            await this.setupContestRoles();

            // 1. Подготовка токенов
            console.log("🔧 Подготовка токенов для тестирования...");
            await this.prepareTokens();

            // 2. Получение начальных балансов
            const addresses = await this.getAddresses();
            const initialBalances = await getMultipleAccountBalances(addresses, this.getTokenAddresses());

            console.log("\n💰 Начальные балансы:");
            await displayMultipleBalances(initialBalances);

            // 3. Создание конкурса
            console.log("\n🏆 Создание конкурса...");
            const contestResult = await this.createContest();

            // 4. Финализация конкурса (выбор победителей и выдача призов)
            console.log("\n🎉 Финализация конкурса...");
            const finalizeResult = await this.finalizeContest(contestResult.escrowAddress);

            // 5. Получение финальных балансов
            const finalBalances = await getMultipleAccountBalances(addresses, this.getTokenAddresses());

            console.log("\n💰 Финальные балансы:");
            await displayMultipleBalances(finalBalances);

            // 6. Анализ изменений балансов
            const balanceChanges = calculateMultipleBalanceChanges(initialBalances, finalBalances);
            console.log("\n📊 Изменения балансов:");
            displayMultipleBalanceChanges(balanceChanges);

            // 7. Анализ комиссий
            const creatorAddress = await this.creator.getAddress();
            const creatorChanges = balanceChanges.find(bc => bc.address === creatorAddress);
            const gatewayChanges = balanceChanges.find(bc => bc.address === this.deployment.addresses.gateway);

            if (creatorChanges && gatewayChanges) {
                await this.analyzeCommissions(creatorChanges, gatewayChanges, contestResult.totalPrizeValue);
            }

            // 8. Построение результата
            const details = await this.buildResultDetails(
                contestResult,
                finalizeResult,
                creatorChanges,
                gatewayChanges,
                finalizeResult.receipt
            );

            console.log(`\n✅ Сценарий "${this.config.contestName}" выполнен успешно!`);
            return new ScenarioResult(this.config.contestName, true, undefined, details);

        } catch (error) {
            console.error(`\n❌ Ошибка в сценарии "${this.config.contestName}":`, error);
            return new ScenarioResult(
                this.config.contestName,
                false,
                error instanceof Error ? error.message : String(error)
            );
        }
    }

    protected async prepareTokens(): Promise<void> {
        console.log("🪙 Подготовка токенов для участников конкурса...");

        // Подготавливаем токены для создателя конкурса
        if (this.deployment.testToken) {
            const amount = ethers.parseEther("1000"); // 1000 токенов для тестирования
            await prepareTokensForTesting(
                this.deployment.testToken,
                this.creator,
                this.deployment.addresses.gateway,
                amount
            );
        }

        // Подготавливаем токены для участников
        for (const participant of this.participants) {
            if (this.deployment.testToken) {
                const amount = ethers.parseEther("100"); // 100 токенов для каждого участника
                await prepareTokensForTesting(
                    this.deployment.testToken,
                    participant,
                    this.deployment.addresses.gateway,
                    amount
                );
            }
        }

        console.log("✅ Токены подготовлены для всех участников");
    }

    protected async setupContestRoles(): Promise<void> {
        console.log("🔐 Настройка ролей для создания конкурсов...");

        // Получаем роль FEATURE_OWNER_ROLE
        const featureOwnerRole = ethers.keccak256(ethers.toUtf8Bytes("FEATURE_OWNER_ROLE"));
        const creatorAddress = await this.creator.getAddress();

        // Проверяем, есть ли уже роль у создателя
        const hasRole = await this.deployment.core.hasRole(featureOwnerRole, creatorAddress);

        if (!hasRole) {
            console.log("⚠️ Выдача роли FEATURE_OWNER_ROLE создателю конкурса...");

            // Получаем деплоера (первый signer), который должен иметь права администратора
            const [deployer] = await ethers.getSigners();

            // Выдаем роль от имени деплоера
            const tx = await this.deployment.core.connect(deployer).grantRole(featureOwnerRole, creatorAddress);
            await tx.wait(); // Ждем подтверждения транзакции
            console.log("✅ Роль FEATURE_OWNER_ROLE выдана создателю конкурса");

            // Проверяем, что роль действительно выдана
            const hasRoleAfter = await this.deployment.core.hasRole(featureOwnerRole, creatorAddress);
            if (!hasRoleAfter) {
                throw new Error("Не удалось выдать роль FEATURE_OWNER_ROLE создателю конкурса");
            }
        } else {
            console.log("✅ Роль FEATURE_OWNER_ROLE уже есть у создателя конкурса");
        }
    }

    protected async getAddresses(): Promise<string[]> {
        const addresses = [await this.creator.getAddress()];
        for (const participant of this.participants) {
            addresses.push(await participant.getAddress());
        }
        addresses.push(this.deployment.addresses.gateway);
        return addresses;
    }

    protected getTokenAddresses(): string[] {
        return [ethers.ZeroAddress, this.deployment.addresses.testToken];
    }

    protected async createContest(): Promise<ContestResult> {
        throw new Error("createContest must be implemented by subclass");
    }

    protected async finalizeContest(escrowAddress: string): Promise<FinalizeResult> {
        throw new Error("finalizeContest must be implemented by subclass");
    }

    protected async analyzeCommissions(
        creatorChanges: BalanceChange,
        gatewayChanges: BalanceChange,
        totalPrizeValue: string
    ): Promise<void> {
        console.log("\n💸 АНАЛИЗ КОМИССИЙ:");
        console.log("=".repeat(40));

        // Анализируем комиссии для каждого токена
        for (const tokenAddress of this.getTokenAddresses()) {
            const tokenSymbol = tokenAddress === ethers.ZeroAddress ? "ETH" : "TEST";

            // Проверяем наличие changes перед использованием find()
            const creatorChange = creatorChanges?.changes?.find(c => c.token === tokenAddress);
            const gatewayChange = gatewayChanges?.changes?.find(c => c.token === tokenAddress);

            if (creatorChange && gatewayChange) {
                console.log(`\n🪙 ${tokenSymbol}:`);
                console.log(`  Создатель потратил: ${ethers.formatEther(Math.abs(Number(creatorChange.change)))} ${tokenSymbol}`);
                console.log(`  Gateway заработал: ${ethers.formatEther(gatewayChange.change)} ${tokenSymbol}`);

                if (Number(creatorChange.change) < 0 && Number(gatewayChange.change) > 0) {
                    const feePercentage = (Number(gatewayChange.change) / Math.abs(Number(creatorChange.change))) * 100;
                    console.log(`  Процент комиссии: ${feePercentage.toFixed(2)}%`);
                }
            }
        }
    }

    protected async buildResultDetails(
        contestResult: ContestResult,
        finalizeResult: FinalizeResult,
        creatorChanges?: BalanceChange,
        gatewayChanges?: BalanceChange,
        receipt?: TransactionReceipt
    ): Promise<ScenarioDetails> {
        const currency = "ETH"; // По умолчанию ETH, может быть переопределено в подклассах

        return new ScenarioDetails(
            contestResult.contestId,
            finalizeResult.winners.length,
            contestResult.totalPrizeValue,
            currency,
            creatorChanges ? ethers.formatEther(Math.abs(Number(creatorChanges.changes[0]?.change || 0))) : "0",
            "Calculated in subclass", // Будет рассчитано в подклассах
            gatewayChanges ? ethers.formatEther(gatewayChanges.changes[0]?.change || 0) : "0",
            receipt ? receipt.gasUsed.toString() : "0"
        );
    }
}
