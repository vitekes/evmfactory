/**
 * Сценарий подписки в ETH
 * 
 * Демонстрирует создание и подписку на план в нативной валюте (ETH):
 * 1. Создание плана подписки в ETH
 * 2. Подписка пользователя на план
 * 3. Анализ балансов и комиссий
 * 4. Проверка активности подписки
 */

import { ethers } from "hardhat";
import { Signer } from "ethers";
import { BaseScenario, ScenarioResult, ScenarioConfig, SubscriptionPlan } from "./base-scenario";

/**
 * Класс для сценария подписки в ETH
 */
export class EthSubscriptionScenario extends BaseScenario {
    constructor(config: ScenarioConfig) {
        super(config);
    }

    async execute(): Promise<ScenarioResult> {
        console.log("\n🎯 СЦЕНАРИЙ: Подписка в ETH");
        console.log("=".repeat(50));

        try {
            const { merchant, subscriber } = await this.getSigners();

            // Анализ балансов до операции
            const addresses = [
                await merchant.getAddress(),
                await subscriber.getAddress(),
                await this.deployment.gateway.getAddress()
            ];
            await this.analyzeBalances(addresses, ethers.ZeroAddress, "до подписки");

            // Создаем план подписки в ETH
            const plan: SubscriptionPlan = {
                id: "eth-monthly",
                name: "Месячная подписка в ETH",
                price: ethers.parseEther("0.01"), // 0.01 ETH
                duration: 30 * 24 * 60 * 60, // 30 дней в секундах
                tokenAddress: ethers.ZeroAddress, // ETH
                merchant: await merchant.getAddress()
            };

            console.log("\n📋 Создание плана подписки в ETH...");
            const { contractPlan, signature } = await this.createSubscriptionPlan(merchant, plan);

            // Подписываемся на план
            console.log("\n✍️ Подписка пользователя на план...");
            const subscriptionTx = await this.deployment.subscriptionManager
                .connect(subscriber)
                .subscribe(contractPlan, signature, "0x", { value: plan.price });

            const subscriptionReceipt = await subscriptionTx.wait();
            console.log("✅ Подписка создана, газ использован:", subscriptionReceipt.gasUsed.toString());

            // Получаем ID подписки из события
            const subscriptionEvent = subscriptionReceipt.logs.find((log: any) => {
                try {
                    const parsed = this.deployment.subscriptionManager.interface.parseLog(log);
                    return parsed?.name === "SubscriptionCreated";
                } catch {
                    return false;
                }
            });

            if (!subscriptionEvent) {
                throw new Error("Не удалось найти событие SubscriptionCreated");
            }

            const parsedSubscriptionEvent = this.deployment.subscriptionManager.interface.parseLog(subscriptionEvent);
            const subscriptionId = parsedSubscriptionEvent.args.subscriptionId;

            console.log("📋 ID подписки:", subscriptionId);

            // Проверяем информацию о подписке
            console.log("\n🔍 Проверка информации о подписке...");
            const subscriptionInfo = await this.getSubscriptionInfo(await subscriber.getAddress());

            if (subscriptionInfo) {
                console.log("✅ Информация о подписке:");
                console.log("  Подписчик:", subscriptionInfo.subscriber);
                console.log("  Мерчант:", subscriptionInfo.merchant);
                console.log("  Токен:", subscriptionInfo.token === ethers.ZeroAddress ? "ETH" : subscriptionInfo.token);
                console.log("  Сумма:", ethers.formatEther(subscriptionInfo.amount), "ETH");
                console.log("  Период:", subscriptionInfo.period, "секунд");
                console.log("  Следующий платеж:", new Date(Number(subscriptionInfo.nextPayment) * 1000).toLocaleString());
                console.log("  Активна:", subscriptionInfo.isActive ? "Да" : "Нет");
            }

            // Анализ балансов после операции
            await this.analyzeBalances(addresses, ethers.ZeroAddress, "после подписки");

            // Проверяем, что подписка активна
            const isActive = subscriptionInfo?.isActive;
            if (!isActive) {
                throw new Error("Подписка не активна после создания");
            }

            console.log("\n🎉 Сценарий подписки в ETH выполнен успешно!");

            return this.createResult(
                "Подписка в ETH",
                true,
                undefined,
                {
                    subscriptionId,
                    planPrice: ethers.formatEther(plan.price),
                    currency: "ETH",
                    duration: plan.duration,
                    merchant: await merchant.getAddress(),
                    subscriber: await subscriber.getAddress(),
                    gasUsed: subscriptionReceipt.gasUsed.toString()
                }
            );

        } catch (error) {
            const errorMessage = error instanceof Error ? error.message : String(error);
            console.log("\n❌ Ошибка в сценарии подписки в ETH:", errorMessage);

            return this.createResult(
                "Подписка в ETH",
                false,
                errorMessage
            );
        }
    }
}

/**
 * Функция-обертка для обратной совместимости
 */
export async function testEthSubscription(
    deployment: any,
    merchant?: Signer,
    subscriber?: Signer
): Promise<ScenarioResult> {
    const scenario = new EthSubscriptionScenario({
        deployment,
        merchant,
        subscriber
    });

    return await scenario.execute();
}
