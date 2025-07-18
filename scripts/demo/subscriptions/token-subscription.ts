/**
 * Сценарий подписки в токенах
 * 
 * Демонстрирует создание и подписку на план в ERC20 токенах:
 * 1. Подготовка токенов для подписчика
 * 2. Создание плана подписки в токенах
 * 3. Approve токенов для SubscriptionManager
 * 4. Подписка пользователя на план
 * 5. Анализ балансов и комиссий
 * 6. Проверка активности подписки
 */

import { ethers } from "hardhat";
import { Signer } from "ethers";
import { BaseScenario, ScenarioResult, ScenarioConfig, SubscriptionPlan } from "./base-scenario";

/**
 * Класс для сценария подписки в токенах
 */
export class TokenSubscriptionScenario extends BaseScenario {
    constructor(config: ScenarioConfig) {
        super(config);
    }

    async execute(): Promise<ScenarioResult> {
        console.log("\n🎯 СЦЕНАРИЙ: Подписка в токенах");
        console.log("=".repeat(50));

        try {
            const { merchant, subscriber } = await this.getSigners();
            const tokenAddress = await this.deployment.testToken.getAddress();

            // Подготавливаем токены для подписчика
            console.log("\n💰 Подготовка токенов для подписчика...");
            const tokenAmount = ethers.parseEther("100"); // 100 токенов
            await this.deployment.testToken.transfer(await subscriber.getAddress(), tokenAmount);
            console.log(`✅ Переведено ${ethers.formatEther(tokenAmount)} токенов подписчику`);

            // Анализ балансов до операции
            const addresses = [
                await merchant.getAddress(),
                await subscriber.getAddress(),
                await this.deployment.gateway.getAddress()
            ];
            await this.analyzeBalances(addresses, tokenAddress, "до подписки");

            // Создаем план подписки в токенах
            const plan: SubscriptionPlan = {
                id: "token-monthly",
                name: "Месячная подписка в токенах",
                price: ethers.parseEther("10"), // 10 токенов
                duration: 30 * 24 * 60 * 60, // 30 дней в секундах
                tokenAddress: tokenAddress,
                merchant: await merchant.getAddress()
            };

            console.log("\n📋 Создание плана подписки в токенах...");
            const { contractPlan, signature } = await this.createSubscriptionPlan(merchant, plan);

            // Approve токенов для PaymentGateway (не для SubscriptionManager!)
            console.log("\n🔓 Approve токенов для PaymentGateway...");
            const paymentGatewayAddress = await this.deployment.gateway.getAddress();
            const approveTx = await this.deployment.testToken
                .connect(subscriber)
                .approve(paymentGatewayAddress, plan.price);
            await approveTx.wait();
            console.log("✅ Токены approved для PaymentGateway");

            // Проверяем allowance
            const allowance = await this.deployment.testToken.allowance(
                await subscriber.getAddress(),
                paymentGatewayAddress
            );
            console.log(`✅ Allowance: ${ethers.formatEther(allowance)} токенов`);

            // Подписываемся на план
            console.log("\n✍️ Подписка пользователя на план...");
            const subscriptionTx = await this.deployment.subscriptionManager
                .connect(subscriber)
                .subscribe(contractPlan, signature, "0x");

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
                console.log("  Токен:", subscriptionInfo.token);
                console.log("  Сумма:", ethers.formatEther(subscriptionInfo.amount), "токенов");
                console.log("  Период:", subscriptionInfo.period, "секунд");
                console.log("  Следующий платеж:", new Date(Number(subscriptionInfo.nextPayment) * 1000).toLocaleString());
                console.log("  Активна:", subscriptionInfo.isActive ? "Да" : "Нет");
            }

            // Анализ балансов после операции
            await this.analyzeBalances(addresses, tokenAddress, "после подписки");

            // Проверяем, что подписка активна
            const isActive = subscriptionInfo?.isActive;
            if (!isActive) {
                throw new Error("Подписка не активна после создания");
            }

            // Проверяем, что токены были переведены
            const subscriberBalanceAfter = await this.deployment.testToken.balanceOf(await subscriber.getAddress());
            const expectedBalance = tokenAmount - plan.price;

            if (subscriberBalanceAfter !== expectedBalance) {
                console.log(`⚠️ Неожиданный баланс подписчика: ${ethers.formatEther(subscriberBalanceAfter)}, ожидался: ${ethers.formatEther(expectedBalance)}`);
            }

            console.log("\n🎉 Сценарий подписки в токенах выполнен успешно!");

            return this.createResult(
                "Подписка в токенах",
                true,
                undefined,
                {
                    subscriptionId,
                    planPrice: ethers.formatEther(plan.price),
                    currency: "TOKENS",
                    duration: plan.duration,
                    merchant: await merchant.getAddress(),
                    subscriber: await subscriber.getAddress(),
                    tokenAddress: tokenAddress,
                    gasUsed: subscriptionReceipt.gasUsed.toString(),
                    subscriberBalanceAfter: ethers.formatEther(subscriberBalanceAfter)
                }
            );

        } catch (error) {
            const errorMessage = error instanceof Error ? error.message : String(error);
            console.log("\n❌ Ошибка в сценарии подписки в токенах:", errorMessage);

            return this.createResult(
                "Подписка в токенах",
                false,
                errorMessage
            );
        }
    }
}

/**
 * Функция-обертка для обратной совместимости
 */
export async function testTokenSubscription(
    deployment: any,
    merchant?: Signer,
    subscriber?: Signer
): Promise<ScenarioResult> {
    const scenario = new TokenSubscriptionScenario({
        deployment,
        merchant,
        subscriber
    });

    return await scenario.execute();
}
