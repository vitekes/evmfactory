import { ethers } from "hardhat";
import { Signer, TransactionReceipt } from "ethers";
import { DeploymentResult } from "../utils/deploy";
import { BalanceChange } from "../utils/balance";
import { 
    BaseScenario, 
    ScenarioResult, 
    ScenarioConfig, 
    ScenarioDetails, 
    ContestPrize,
    ContestResult,
    FinalizeResult,
    ParsedLogResult,
    ContestCreatedEventArgs,
    MonetaryPrizePaidEventArgs,
    PromoPrizeIssuedEventArgs
} from "./base-scenario";

/**
 * Сценарий тестирования смешанного конкурса (денежные + промо-призы)
 * 
 * Этот сценарий тестирует:
 * 1. Создание конкурса с комбинацией денежных и промо-призов
 * 2. Финансирование только денежных призов
 * 3. Финализацию конкурса с выбором победителей
 * 4. Выдачу как денежных, так и промо-призов
 * 5. Анализ комиссий только с денежных призов
 * 6. Проверку корректной обработки разных типов призов
 */
export class MixedContestScenario extends BaseScenario {
    private prizes: ContestPrize[];
    private totalMonetaryAmount: bigint;

    constructor(deployment: DeploymentResult, creator: Signer, participants: Signer[]) {
        super(
            deployment,
            creator,
            participants,
            new ScenarioConfig(
                "Смешанный конкурс (ETH + Промо)",
                "Создание конкурса с комбинацией денежных и промо-призов, финализация и выдача разных типов призов",
                "Успешное создание конкурса, выдача денежных и промо-призов, корректное списание комиссий только с денежных призов"
            )
        );

        // Настройка смешанных призов: денежные и промо-призы
        this.totalMonetaryAmount = ethers.parseEther("0.6"); // 0.6 ETH для денежных призов
        this.prizes = [
            {
                prizeType: 0, // MONETARY
                token: ethers.ZeroAddress, // ETH
                amount: ethers.parseEther("0.4").toString(), // 1-е место: 0.4 ETH
                distribution: 0, // flat distribution
                uri: ""
            },
            {
                prizeType: 1, // PROMO
                token: ethers.ZeroAddress, // Не используется для промо-призов
                amount: "0", // Не используется для промо-призов
                distribution: 0, // Не используется для промо-призов
                uri: "https://example.com/promo/premium-access"
            },
            {
                prizeType: 0, // MONETARY
                token: ethers.ZeroAddress, // ETH
                amount: ethers.parseEther("0.2").toString(), // 3-е место: 0.2 ETH
                distribution: 0, // flat distribution
                uri: ""
            },
            {
                prizeType: 1, // PROMO
                token: ethers.ZeroAddress,
                amount: "0",
                distribution: 0,
                uri: "https://example.com/promo/special-badge"
            }
        ];
    }

    protected async createContest(): Promise<ContestResult> {
        console.log("🎯 Создание смешанного конкурса с денежными и промо-призами...");
        console.log(`🏆 Общий денежный фонд: ${ethers.formatEther(this.totalMonetaryAmount)} ETH`);
        console.log("🏅 Призы:");
        console.log("🥇 1-е место: 0.4 ETH (денежный)");
        console.log("🥈 2-е место: Премиум доступ (промо)");
        console.log("🥉 3-е место: 0.2 ETH (денежный)");
        console.log("🏷️ 4-е место: Специальный значок (промо)");

        // Получаем контракт фабрики конкурсов
        const contestFactory = await ethers.getContractAt(
            "ContestFactory",
            this.deployment.addresses.contestFactory
        );

        // Создаем конкурс с отправкой ETH только для денежных призов
        // Используем staticCall для получения возвращаемого значения (адреса эскроу)
        const escrowAddress = await contestFactory
            .connect(this.creator)
            .createContest.staticCall(this.prizes, "0x", {
                value: this.totalMonetaryAmount
            });

        // Теперь выполняем реальную транзакцию
        const tx = await contestFactory
            .connect(this.creator)
            .createContest(this.prizes, "0x", {
                value: this.totalMonetaryAmount
            });

        const receipt = await tx.wait();
        console.log("✅ Транзакция создания конкурса подтверждена");
        console.log(`⛽ Газ использован: ${receipt.gasUsed.toString()}`);

        // Проверяем наличие receipt и logs
        if (!receipt || !receipt.logs) {
            throw new Error("Не удалось получить логи транзакции создания конкурса");
        }

        // Извлекаем ID конкурса из событий
        const contestCreatedEvent = receipt.logs.find((log: any) => {
            try {
                const parsed = contestFactory.interface.parseLog(log) as ParsedLogResult;
                return parsed?.name === "ContestCreated";
            } catch {
                return false;
            }
        });

        if (!contestCreatedEvent) {
            throw new Error("Событие ContestCreated не найдено");
        }

        const parsedEvent = contestFactory.interface.parseLog(contestCreatedEvent) as ParsedLogResult;
        const eventArgs = parsedEvent.args as ContestCreatedEventArgs;
        const contestId = eventArgs.contestId.toString();

        console.log(`🆔 ID конкурса: ${contestId}`);
        console.log(`📦 Адрес эскроу: ${escrowAddress}`);

        return {
            escrowAddress,
            contestId,
            totalPrizeValue: ethers.formatEther(this.totalMonetaryAmount),
            receipt
        };
    }

    protected async finalizeContest(escrowAddress: string): Promise<FinalizeResult> {
        console.log("🎯 Финализация смешанного конкурса...");

        // Выбираем победителей из участников
        const winners = [];
        for (let i = 0; i < Math.min(this.prizes.length, this.participants.length); i++) {
            winners.push(await this.participants[i].getAddress());
        }

        console.log("🏆 Победители:");
        winners.forEach((winner, index) => {
            const place = this.getPlaceEmoji(index);
            const prizeDescription = this.getPrizeDescription(index);
            console.log(`  ${place} ${winner}: ${prizeDescription}`);
        });

        // Получаем контракт эскроу
        const contestEscrow = await ethers.getContractAt("ContestEscrow", escrowAddress);

        // Финализируем конкурс
        const priorityCap = ethers.parseUnits("20", "gwei"); // 20 gwei priority fee cap
        const tx = await contestEscrow
            .connect(this.creator)
            .finalize(winners, priorityCap);

        const receipt = await tx.wait();
        console.log("✅ Конкурс финализирован");
        console.log(`⛽ Газ использован: ${receipt.gasUsed.toString()}`);

        // Проверяем наличие receipt и logs
        if (!receipt || !receipt.logs) {
            throw new Error("Не удалось получить логи транзакции финализации конкурса");
        }

        // Проверяем события выдачи денежных призов
        const monetaryEvents = receipt.logs.filter((log: any) => {
            try {
                const parsed = contestEscrow.interface.parseLog(log) as ParsedLogResult;
                return parsed?.name === "MonetaryPrizePaid";
            } catch {
                return false;
            }
        });

        // Проверяем события выдачи промо-призов
        const promoEvents = receipt.logs.filter((log: any) => {
            try {
                const parsed = contestEscrow.interface.parseLog(log) as ParsedLogResult;
                return parsed?.name === "PromoPrizeIssued";
            } catch {
                return false;
            }
        });

        console.log(`💰 Выдано денежных призов: ${monetaryEvents.length}`);
        monetaryEvents.forEach((event: any, index: number) => {
            const parsed = contestEscrow.interface.parseLog(event) as ParsedLogResult;
            const eventArgs = parsed.args as MonetaryPrizePaidEventArgs;
            const winner = eventArgs.to;
            const amount = ethers.formatEther(eventArgs.amount);
            console.log(`  Денежный приз ${index + 1}: ${winner} получил ${amount} ETH`);
        });

        console.log(`🎁 Выдано промо-призов: ${promoEvents.length}`);
        promoEvents.forEach((event: any, index: number) => {
            const parsed = contestEscrow.interface.parseLog(event) as ParsedLogResult;
            const eventArgs = parsed.args as PromoPrizeIssuedEventArgs;
            const slot = eventArgs.slot;
            const winner = eventArgs.to;
            const uri = eventArgs.uri;
            console.log(`  Промо-приз ${Number(slot) + 1}: ${winner}`);
            console.log(`    URI: ${uri}`);
        });

        return {
            winners,
            receipt
        };
    }

    private getPlaceEmoji(index: number): string {
        switch (index) {
            case 0: return "🥇";
            case 1: return "🥈";
            case 2: return "🥉";
            case 3: return "🏷️";
            default: return "🏅";
        }
    }

    private getPrizeDescription(index: number): string {
        const prize = this.prizes[index];
        if (prize.prizeType === 0) { // MONETARY
            return `${ethers.formatEther(prize.amount)} ETH (денежный)`;
        } else { // PROMO
            switch (index) {
                case 1: return "Премиум доступ (промо)";
                case 3: return "Специальный значок (промо)";
                default: return "Промо-приз";
            }
        }
    }

    protected async buildResultDetails(
        contestResult: ContestResult,
        finalizeResult: FinalizeResult,
        creatorChanges?: any,
        gatewayChanges?: any,
        receipt?: TransactionReceipt
    ): Promise<ScenarioDetails> {
        // Рассчитываем общую сумму денежных призов, полученную победителями
        let totalMonetaryReceived = 0n;
        let promoCount = 0;

        for (const prize of this.prizes) {
            if (prize.prizeType === 0) { // MONETARY
                totalMonetaryReceived += BigInt(prize.amount);
            } else { // PROMO
                promoCount++;
            }
        }

        const winnersReceived = `${ethers.formatEther(totalMonetaryReceived)} ETH + ${promoCount} промо`;

        return new ScenarioDetails(
            contestResult.contestId,
            this.prizes.length,
            contestResult.totalPrizeValue,
            "MIXED",
            creatorChanges?.changes?.[0] ? ethers.formatEther(Math.abs(Number(creatorChanges.changes[0].change || 0))) : "0",
            winnersReceived,
            gatewayChanges?.changes?.[0] ? ethers.formatEther(gatewayChanges.changes[0].change || 0) : "0",
            receipt ? receipt.gasUsed.toString() : "0"
        );
    }

    protected async analyzeCommissions(
        creatorChanges: BalanceChange,
        gatewayChanges: BalanceChange,
        totalPrizeValue: string
    ): Promise<void> {
        console.log("\n💸 АНАЛИЗ КОМИССИЙ:");
        console.log("=".repeat(40));
        console.log("🎯 Смешанный конкурс: комиссии только с денежных призов");
        console.log(`💰 Денежные призы: ${ethers.formatEther(this.totalMonetaryAmount)} ETH`);
        console.log("🎁 Промо-призы: без комиссий");

        // Анализируем комиссии для каждого токена
        for (const tokenAddress of this.getTokenAddresses()) {
            const tokenSymbol = tokenAddress === ethers.ZeroAddress ? "ETH" : "TEST";

            const creatorChange = creatorChanges?.changes?.find((c: any) => c.token === tokenAddress);
            const gatewayChange = gatewayChanges?.changes?.find((c: any) => c.token === tokenAddress);

            if (creatorChange && gatewayChange) {
                console.log(`\n🪙 ${tokenSymbol}:`);
                console.log(`  Создатель потратил: ${ethers.formatEther(Math.abs(Number(creatorChange.change)))} ${tokenSymbol}`);
                console.log(`  Gateway заработал: ${ethers.formatEther(gatewayChange.change)} ${tokenSymbol}`);

                if (Number(creatorChange.change) < 0 && Number(gatewayChange.change) > 0) {
                    const feePercentage = (Number(gatewayChange.change) / Math.abs(Number(creatorChange.change))) * 100;
                    console.log(`  Процент комиссии: ${feePercentage.toFixed(2)}%`);
                }

                // Показываем разбивку по типам призов
                const monetarySpent = Number(this.totalMonetaryAmount);
                const gasSpent = Math.abs(Number(creatorChange.change)) - monetarySpent;
                console.log(`  Из них:`);
                console.log(`    На денежные призы: ${ethers.formatEther(monetarySpent)} ${tokenSymbol}`);
                console.log(`    На газ: ${ethers.formatEther(gasSpent)} ${tokenSymbol}`);
            }
        }
    }
}

/**
 * Функция-обертка для запуска сценария смешанного конкурса
 */
export async function testMixedContest(
    deployment: DeploymentResult,
    creator: Signer,
    participants: Signer[]
): Promise<ScenarioResult> {
    const scenario = new MixedContestScenario(deployment, creator, participants);
    return await scenario.execute();
}
