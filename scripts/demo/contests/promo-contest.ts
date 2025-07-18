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
    PromoPrizeIssuedEventArgs
} from "./base-scenario";

/**
 * Сценарий тестирования неденежного конкурса (промо-призы)
 * 
 * Этот сценарий тестирует:
 * 1. Создание конкурса с промо-призами (неденежными)
 * 2. Финализацию конкурса с выбором победителей
 * 3. Выдачу промо-призов (события с URI)
 * 4. Проверку отсутствия денежных транзакций
 * 5. Анализ газовых затрат без денежных переводов
 */
export class PromoContestScenario extends BaseScenario {
    private prizes: ContestPrize[];

    constructor(deployment: DeploymentResult, creator: Signer, participants: Signer[]) {
        super(
            deployment,
            creator,
            participants,
            new ScenarioConfig(
                "Неденежный конкурс (Промо-призы)",
                "Создание конкурса с промо-призами, финализация и выдача неденежных призов",
                "Успешное создание конкурса, выдача промо-призов через события, минимальные газовые затраты"
            )
        );

        // Настройка промо-призов: 3 места с разными промо-кодами
        this.prizes = [
            {
                prizeType: 1, // PROMO
                token: ethers.ZeroAddress, // Не используется для промо-призов
                amount: "0", // Не используется для промо-призов
                distribution: 0, // Не используется для промо-призов
                uri: "https://example.com/promo/gold-membership"
            },
            {
                prizeType: 1, // PROMO
                token: ethers.ZeroAddress,
                amount: "0",
                distribution: 0,
                uri: "https://example.com/promo/silver-discount-50"
            },
            {
                prizeType: 1, // PROMO
                token: ethers.ZeroAddress,
                amount: "0",
                distribution: 0,
                uri: "https://example.com/promo/bronze-bonus-pack"
            }
        ];
    }

    protected async createContest(): Promise<ContestResult> {
        console.log("🎁 Создание неденежного конкурса с промо-призами...");
        console.log("🏆 Призы:");
        console.log("🥇 1-е место: Золотое членство");
        console.log("🥈 2-е место: Скидка 50%");
        console.log("🥉 3-е место: Бонусный пакет");

        // Получаем контракт фабрики конкурсов
        const contestFactory = await ethers.getContractAt(
            "ContestFactory",
            this.deployment.addresses.contestFactory
        );

        // Создаем конкурс без отправки ETH (промо-призы не требуют финансирования)
        // Используем staticCall для получения возвращаемого значения (адреса эскроу)
        const escrowAddress = await contestFactory
            .connect(this.creator)
            .createContest.staticCall(this.prizes, "0x");

        // Теперь выполняем реальную транзакцию
        const tx = await contestFactory
            .connect(this.creator)
            .createContest(this.prizes, "0x");

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
            totalPrizeValue: "0", // Промо-призы не имеют денежной стоимости
            receipt
        };
    }

    protected async finalizeContest(escrowAddress: string): Promise<FinalizeResult> {
        console.log("🎯 Финализация неденежного конкурса...");

        // Выбираем победителей из участников
        const winners = [];
        for (let i = 0; i < Math.min(this.prizes.length, this.participants.length); i++) {
            winners.push(await this.participants[i].getAddress());
        }

        console.log("🏆 Победители:");
        winners.forEach((winner, index) => {
            const place = index === 0 ? "🥇" : index === 1 ? "🥈" : "🥉";
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

        // Проверяем события выдачи промо-призов
        const promoEvents = receipt.logs.filter((log: any) => {
            try {
                const parsed = contestEscrow.interface.parseLog(log);
                return parsed?.name === "PromoPrizeIssued";
            } catch {
                return false;
            }
        });

        console.log(`🎁 Выдано промо-призов: ${promoEvents.length}`);
        promoEvents.forEach((event: any, index: number) => {
            const parsed = contestEscrow.interface.parseLog(event);
            const slot = parsed.args.slot;
            const winner = parsed.args.to;
            const uri = parsed.args.uri;
            console.log(`  Промо-приз ${Number(slot) + 1}: ${winner}`);
            console.log(`    URI: ${uri}`);
        });

        return {
            winners,
            receipt
        };
    }

    private getPrizeDescription(index: number): string {
        switch (index) {
            case 0: return "Золотое членство";
            case 1: return "Скидка 50%";
            case 2: return "Бонусный пакет";
            default: return "Промо-приз";
        }
    }

    protected async buildResultDetails(
        contestResult: any,
        finalizeResult: any,
        creatorChanges?: any,
        gatewayChanges?: any,
        receipt?: TransactionReceipt
    ): Promise<ScenarioDetails> {
        return new ScenarioDetails(
            contestResult.contestId,
            this.prizes.length,
            "0", // Промо-призы не имеют денежной стоимости
            "PROMO",
            "0", // Создатель не тратит деньги на промо-призы
            `${this.prizes.length} промо-призов`, // Количество выданных промо-призов
            "0", // Gateway не получает комиссию с промо-призов
            receipt ? receipt.gasUsed.toString() : "0"
        );
    }

    protected async analyzeCommissions(
        creatorChanges: any,
        gatewayChanges: any,
        totalPrizeValue: string
    ): Promise<void> {
        console.log("\n💸 АНАЛИЗ КОМИССИЙ:");
        console.log("=".repeat(40));
        console.log("🎁 Промо-конкурс: комиссии не взимаются");
        console.log("💰 Денежные переводы: отсутствуют");
        console.log("⛽ Затраты: только газ на выполнение транзакций");

        // Анализируем только газовые затраты
        for (const tokenAddress of this.getTokenAddresses()) {
            const tokenSymbol = tokenAddress === ethers.ZeroAddress ? "ETH" : "TEST";

            const creatorChange = creatorChanges?.changes?.find((c: any) => c.token === tokenAddress);

            if (creatorChange && Number(creatorChange.change) < 0) {
                console.log(`\n🪙 ${tokenSymbol} (только газ):`);
                console.log(`  Создатель потратил на газ: ${ethers.formatEther(Math.abs(Number(creatorChange.change)))} ${tokenSymbol}`);
            }
        }
    }
}

/**
 * Функция-обертка для запуска сценария неденежного конкурса
 */
export async function testPromoContest(
    deployment: DeploymentResult,
    creator: Signer,
    participants: Signer[]
): Promise<ScenarioResult> {
    const scenario = new PromoContestScenario(deployment, creator, participants);
    return await scenario.execute();
}
