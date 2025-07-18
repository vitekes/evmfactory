/**
 * Сценарий отмены подписки
 * 
 * Демонстрирует процесс отмены подписки:
 * 1. Создание подписки в ETH
 * 2. Проверка активности подписки
 * 3. Отмена подписки пользователем
 * 4. Проверка статуса после отмены
 * 5. Анализ балансов и возвратов
 */

import { ethers } from "hardhat";
import { Signer, Log } from "ethers";
import { BaseScenario, ScenarioResult, ScenarioConfig, SubscriptionPlan, SubscriptionDeployment } from "./base-scenario";

/**
 * Класс для сценария отмены подписки
 */
export class SubscriptionCancellationScenario extends BaseScenario {
    constructor(config: ScenarioConfig) {
        super(config);
    }

    async execute(): Promise<ScenarioResult> {
        console.log("\n🎯 СЦЕНАРИЙ: Отмена подписки");
        console.log("=".repeat(50));

        try {
            const { merchant, subscriber } = await this.getSigners();

            // Анализ балансов до операции
            const addresses = [
                await merchant.getAddress(),
                await subscriber.getAddress(),
                await this.deployment.gateway.getAddress()
            ];
            await this.analyzeBalances(addresses, ethers.ZeroAddress, "до создания подписки");

            // Создаем план подписки в ETH
            const plan: SubscriptionPlan = {
                id: "eth-cancellation-test",
                name: "Тестовая подписка для отмены",
                price: ethers.parseEther("0.005"), // 0.005 ETH
                duration: 7 * 24 * 60 * 60, // 7 дней в секундах
                tokenAddress: ethers.ZeroAddress, // ETH
                merchant: await merchant.getAddress()
            };

            console.log("\n📋 Создание плана подписки для тестирования отмены...");
            const { contractPlan, signature } = await this.createSubscriptionPlan(merchant, plan);

            // Подписываемся на план
            console.log("\n✍️ Создание подписки...");
            const subscriptionTx = await this.deployment.subscriptionManager
                .connect(subscriber)
                .subscribe(contractPlan, signature, "0x", { value: plan.price });

            const subscriptionReceipt = await subscriptionTx.wait();
            console.log("✅ Подписка создана, газ использован:", subscriptionReceipt.gasUsed.toString());

            // Получаем ID подписки из события
            const subscriptionEvent = subscriptionReceipt.logs.find((log: Log) => {
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
            if (!parsedSubscriptionEvent) {
                throw new Error("Не удалось распарсить событие SubscriptionCreated");
            }
            const subscriptionId = parsedSubscriptionEvent.args.subscriptionId;

            console.log("📋 ID подписки:", subscriptionId);

            // Проверяем информацию о подписке до отмены
            console.log("\n🔍 Проверка информации о подписке до отмены...");
            const subscriptionInfoBefore = await this.getSubscriptionInfo(await subscriber.getAddress());

            if (subscriptionInfoBefore) {
                console.log("✅ Информация о подписке до отмены:");
                console.log("  Подписчик:", subscriptionInfoBefore.subscriber);
                console.log("  Мерчант:", subscriptionInfoBefore.merchant);
                console.log("  Токен:", subscriptionInfoBefore.token === ethers.ZeroAddress ? "ETH" : subscriptionInfoBefore.token);
                console.log("  Сумма:", ethers.formatEther(subscriptionInfoBefore.amount), "ETH");
                console.log("  Период:", subscriptionInfoBefore.period, "секунд");
                console.log("  Следующий платеж:", new Date(Number(subscriptionInfoBefore.nextPayment) * 1000).toLocaleString());
                console.log("  Активна:", subscriptionInfoBefore.isActive ? "Да" : "Нет");
            }

            // Проверяем, что подписка активна
            if (!subscriptionInfoBefore?.isActive) {
                throw new Error("Подписка не активна после создания");
            }

            // Анализ балансов после создания подписки
            await this.analyzeBalances(addresses, ethers.ZeroAddress, "после создания подписки");

            // Отменяем подписку
            console.log("\n❌ Отмена подписки пользователем...");
            const cancelTx = await this.deployment.subscriptionManager
                .connect(subscriber)
                .unsubscribe();

            const cancelReceipt = await cancelTx.wait();
            console.log("✅ Подписка отменена, газ использован:", cancelReceipt.gasUsed.toString());

            // Проверяем событие отмены
            const cancelEvent = cancelReceipt.logs.find((log: Log) => {
                try {
                    const parsed = this.deployment.subscriptionManager.interface.parseLog(log);
                    return parsed?.name === "SubscriptionCancelled";
                } catch {
                    return false;
                }
            });

            if (cancelEvent) {
                const parsedCancelEvent = this.deployment.subscriptionManager.interface.parseLog(cancelEvent);
                if (parsedCancelEvent) {
                    console.log("✅ Событие отмены найдено:", parsedCancelEvent.args);
                } else {
                    console.log("⚠️ Не удалось распарсить событие отмены");
                }
            } else {
                console.log("⚠️ Событие отмены не найдено");
            }

            // Проверяем информацию о подписке после отмены
            console.log("\n🔍 Проверка информации о подписке после отмены...");
            const subscriptionInfoAfter = await this.getSubscriptionInfo(await subscriber.getAddress());

            if (subscriptionInfoAfter) {
                console.log("✅ Информация о подписке после отмены:");
                console.log("  Подписчик:", subscriptionInfoAfter.subscriber);
                console.log("  Мерчант:", subscriptionInfoAfter.merchant);
                console.log("  Токен:", subscriptionInfoAfter.token === ethers.ZeroAddress ? "ETH" : subscriptionInfoAfter.token);
                console.log("  Сумма:", ethers.formatEther(subscriptionInfoAfter.amount), "ETH");
                console.log("  Период:", subscriptionInfoAfter.period, "секунд");
                console.log("  Следующий платеж:", new Date(Number(subscriptionInfoAfter.nextPayment) * 1000).toLocaleString());
                console.log("  Активна:", subscriptionInfoAfter.isActive ? "Да" : "Нет");
            }

            // Проверяем, что подписка неактивна
            if (subscriptionInfoAfter?.isActive) {
                throw new Error("Подписка все еще активна после отмены");
            }

            // Анализ балансов после отмены
            await this.analyzeBalances(addresses, ethers.ZeroAddress, "после отмены подписки");

            // Проверяем, что нельзя отменить уже отмененную подписку
            console.log("\n🔄 Попытка повторной отмены...");
            try {
                await this.deployment.subscriptionManager
                    .connect(subscriber)
                    .unsubscribe();
                console.log("⚠️ Повторная отмена прошла успешно (неожиданно)");
            } catch (error) {
                console.log("✅ Повторная отмена заблокирована (ожидаемо):", error instanceof Error ? error.message : String(error));
            }

            console.log("\n🎉 Сценарий отмены подписки выполнен успешно!");

            return this.createResult(
                "Отмена подписки",
                true,
                undefined,
                {
                    subscriptionId,
                    planPrice: ethers.formatEther(plan.price),
                    currency: "ETH",
                    duration: plan.duration,
                    merchant: await merchant.getAddress(),
                    subscriber: await subscriber.getAddress(),
                    subscriptionGasUsed: subscriptionReceipt.gasUsed.toString(),
                    cancellationGasUsed: cancelReceipt.gasUsed.toString(),
                    wasActiveBefore: subscriptionInfoBefore?.isActive,
                    isActiveAfter: subscriptionInfoAfter?.isActive
                }
            );

        } catch (error) {
            const errorMessage = error instanceof Error ? error.message : String(error);
            console.log("\n❌ Ошибка в сценарии отмены подписки:", errorMessage);

            return this.createResult(
                "Отмена подписки",
                false,
                errorMessage
            );
        }
    }
}

/**
 * Функция-обертка для обратной совместимости
 */
export async function testSubscriptionCancellation(
    deployment: SubscriptionDeployment,
    merchant?: Signer,
    subscriber?: Signer
): Promise<ScenarioResult> {
    const scenario = new SubscriptionCancellationScenario({
        deployment,
        merchant,
        subscriber
    });

    return await scenario.execute();
}
