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
    MonetaryPrizePaidEventArgs
} from "./base-scenario";

/**
 * Сценарий тестирования денежного конкурса
 * 
 * Этот сценарий тестирует:
 * 1. Создание конкурса с денежными призами в ETH
 * 2. Финансирование конкурса создателем
 * 3. Финализацию конкурса с выбором победителей
 * 4. Выдачу денежных призов победителям
 * 5. Анализ комиссий платёжного шлюза
 */
export class MonetaryContestScenario extends BaseScenario {
    private prizes: ContestPrize[];
    private totalPrizeAmount: bigint;

    constructor(deployment: DeploymentResult, creator: Signer, participants: Signer[]) {
        super(
            deployment,
            creator,
            participants,
            new ScenarioConfig(
                "Денежный конкурс (ETH)",
                "Создание конкурса с денежными призами в ETH, финализация и выдача призов",
                "Успешное создание конкурса, выдача призов победителям, корректное списание комиссий"
            )
        );

        // Настройка призов: 3 места с убывающими суммами
        this.totalPrizeAmount = ethers.parseEther("1.0"); // 1 ETH общий призовой фонд
        this.prizes = [
            {
                prizeType: 0, // MONETARY
                token: ethers.ZeroAddress, // ETH
                amount: ethers.parseEther("0.5").toString(), // 1-е место: 0.5 ETH
                distribution: 0, // flat distribution
                uri: ""
            },
            {
                prizeType: 0, // MONETARY
                token: ethers.ZeroAddress, // ETH
                amount: ethers.parseEther("0.3").toString(), // 2-е место: 0.3 ETH
                distribution: 0, // flat distribution
                uri: ""
            },
            {
                prizeType: 0, // MONETARY
                token: ethers.ZeroAddress, // ETH
                amount: ethers.parseEther("0.2").toString(), // 3-е место: 0.2 ETH
                distribution: 0, // flat distribution
                uri: ""
            }
        ];
    }

    protected async createContest(): Promise<ContestResult> {
        console.log("💰 Создание денежного конкурса с призами в ETH...");
        console.log(`🏆 Призовой фонд: ${ethers.formatEther(this.totalPrizeAmount)} ETH`);
        console.log("🥇 1-е место: 0.5 ETH");
        console.log("🥈 2-е место: 0.3 ETH");
        console.log("🥉 3-е место: 0.2 ETH");

        // Получаем контракт фабрики конкурсов
        const contestFactory = await ethers.getContractAt(
            "ContestFactory",
            this.deployment.addresses.contestFactory
        );

        // Создаем конкурс с отправкой ETH для финансирования призов
        // Используем staticCall для получения возвращаемого значения (адреса эскроу)
        const escrowAddress = await contestFactory
            .connect(this.creator)
            .createContest.staticCall(this.prizes, "0x", {
                value: this.totalPrizeAmount
            });

        // Теперь выполняем реальную транзакцию
        const tx = await contestFactory
            .connect(this.creator)
            .createContest(this.prizes, "0x", {
                value: this.totalPrizeAmount
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
            totalPrizeValue: ethers.formatEther(this.totalPrizeAmount),
            receipt
        };
    }

    protected async finalizeContest(escrowAddress: string): Promise<FinalizeResult> {
        console.log("🎯 Финализация денежного конкурса...");

        // Выбираем победителей из участников
        const winners = [];
        for (let i = 0; i < Math.min(this.prizes.length, this.participants.length); i++) {
            winners.push(await this.participants[i].getAddress());
        }

        console.log("🏆 Победители:");
        winners.forEach((winner, index) => {
            const place = index === 0 ? "🥇" : index === 1 ? "🥈" : "🥉";
            const prize = ethers.formatEther(this.prizes[index].amount);
            console.log(`  ${place} ${winner}: ${prize} ETH`);
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

        // Проверяем события выдачи призов
        const prizeEvents = receipt.logs.filter((log: any) => {
            try {
                const parsed = contestEscrow.interface.parseLog(log) as ParsedLogResult;
                return parsed?.name === "MonetaryPrizePaid";
            } catch {
                return false;
            }
        });

        console.log(`🎁 Выдано призов: ${prizeEvents.length}`);
        prizeEvents.forEach((event: any, index: number) => {
            const parsed = contestEscrow.interface.parseLog(event) as ParsedLogResult;
            const eventArgs = parsed.args as MonetaryPrizePaidEventArgs;
            const winner = eventArgs.to;
            const amount = ethers.formatEther(eventArgs.amount);
            console.log(`  Приз ${index + 1}: ${winner} получил ${amount} ETH`);
        });

        return {
            winners,
            receipt
        };
    }

    protected async buildResultDetails(
        contestResult: ContestResult,
        finalizeResult: FinalizeResult,
        creatorChanges?: BalanceChange,
        gatewayChanges?: BalanceChange,
        receipt?: TransactionReceipt
    ): Promise<ScenarioDetails> {
        // Рассчитываем общую сумму, полученную победителями
        let totalWinnersReceived = 0n;
        for (const prize of this.prizes) {
            totalWinnersReceived += BigInt(prize.amount);
        }

        return new ScenarioDetails(
            contestResult.contestId,
            this.prizes.length,
            contestResult.totalPrizeValue,
            "ETH",
            creatorChanges?.changes?.[0] ? ethers.formatEther(Math.abs(Number(creatorChanges.changes[0].change || 0))) : "0",
            ethers.formatEther(totalWinnersReceived),
            gatewayChanges?.changes?.[0] ? ethers.formatEther(gatewayChanges.changes[0].change || 0) : "0",
            receipt ? receipt.gasUsed.toString() : "0"
        );
    }
}

/**
 * Функция-обертка для запуска сценария денежного конкурса
 */
export async function testMonetaryContest(
    deployment: DeploymentResult,
    creator: Signer,
    participants: Signer[]
): Promise<ScenarioResult> {
    const scenario = new MonetaryContestScenario(deployment, creator, participants);
    return await scenario.execute();
}
