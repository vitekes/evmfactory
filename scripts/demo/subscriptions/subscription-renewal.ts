/**
 * Сценарий продления подписки (Renewal)
 * 
 * Демонстрирует механизм автоматического продления подписки через charge()
 * Включает анализ балансов и проверку корректности списания средств
 */

import { ethers } from "hardhat";
import { Signer } from "ethers";
import { BaseScenario, ScenarioResult, ScenarioConfig, SubscriptionDeployment } from './base-scenario';

export class SubscriptionRenewalScenario extends BaseScenario {
    constructor(config: ScenarioConfig) {
        super(config);
    }

    async execute(): Promise<ScenarioResult> {
        try {
            console.log("\n🔄 СЦЕНАРИЙ ПРОДЛЕНИЯ ПОДПИСКИ");
            console.log("=".repeat(50));

            const { merchant, subscriber } = await this.getSigners();
            const [deployer] = await ethers.getSigners();

            // Создаем план подписки с использованием тестового токена
            const plan = await this.createSubscriptionPlan(merchant, {
                id: "renewal-test-plan",
                name: "Тестовый план для продления",
                price: ethers.parseEther("10"), // 10 токенов
                duration: 15, // 15 секунд для быстрого тестирования
                tokenAddress: await this.deployment.testToken.getAddress(), // Используем тестовый токен
                merchant: await merchant.getAddress()
            });

            console.log("📋 План подписки создан:");
            console.log("  💰 Цена:", plan.contractPlan.price ? ethers.formatEther(plan.contractPlan.price) : "0", "TOKENS");
            console.log("  ⏰ Период:", plan.contractPlan.period, "секунд");
            console.log("  🏪 Мерчант:", plan.contractPlan.merchant);

            // Анализируем балансы до подписки
            const addresses = [
                await merchant.getAddress(),
                await subscriber.getAddress()
            ];

            await this.analyzeBalances(addresses, await this.deployment.testToken.getAddress(), "До подписки");

            // Подписываемся на план
            console.log("\n📝 Создание подписки...");

            // Переводим токены подписчику для тестирования
            const transferAmount = ethers.parseEther("100"); // 100 токенов
            await this.deployment.testToken.connect(deployer).transfer(await subscriber.getAddress(), transferAmount);
            console.log("✅ Токены переданы подписчику");

            // Подписчик одобряет контракт для трат токенов (PaymentGateway, не SubscriptionManager!)
            const approveAmount = plan.contractPlan.price * 10n; // Одобряем больше для нескольких платежей
            const paymentGatewayAddress = await this.deployment.gateway.getAddress();
            await this.deployment.testToken.connect(subscriber).approve(
                paymentGatewayAddress,
                approveAmount
            );
            console.log("✅ Токены одобрены для PaymentGateway");

            const subscribeTx = await this.deployment.subscriptionManager
                .connect(subscriber)
                .subscribe(plan.contractPlan, plan.signature, "0x");

            const subscribeReceipt = await subscribeTx.wait();
            console.log("✅ Подписка создана, газ:", subscribeReceipt.gasUsed.toString());

            // Анализируем балансы после подписки
            await this.analyzeBalances(addresses, await this.deployment.testToken.getAddress(), "После подписки");

            // Получаем информацию о подписке
            const subscriptionInfo = await this.getSubscriptionInfo(await subscriber.getAddress());
            console.log("\n📊 Информация о подписке:");
            console.log("  📋 Plan Hash:", subscriptionInfo.planHash);
            console.log("  ⏰ Следующее списание:", new Date(Number(subscriptionInfo.nextBilling) * 1000).toLocaleString());

            // Ждем до времени следующего списания
            console.log("\n⏳ Ожидание времени продления...");
            const currentTime = Math.floor(Date.now() / 1000);
            const waitTime = Number(subscriptionInfo.nextBilling) - currentTime + 5; // +5 секунд для уверенности

            if (waitTime > 0) {
                console.log(`  ⏰ Ожидание ${waitTime} секунд...`);
                await new Promise(resolve => setTimeout(resolve, waitTime * 1000));
            }

            // Настраиваем роль AUTOMATION_ROLE для возможности вызова charge()
            console.log("\n🔐 Настройка роли AUTOMATION_ROLE...");
            const automationRole = ethers.keccak256(ethers.toUtf8Bytes("AUTOMATION_ROLE"));

            const hasAutomationRole = await this.deployment.core.hasRole(automationRole, await deployer.getAddress());
            if (!hasAutomationRole) {
                await this.deployment.core.grantRole(automationRole, await deployer.getAddress());
                console.log("✅ Роль AUTOMATION_ROLE выдана деплоеру");
            } else {
                console.log("✅ Роль AUTOMATION_ROLE уже есть у деплоера");
            }

            // Проверяем достаточность токенов для продления
            console.log("\n💰 Проверка токенов для продления...");
            const subscriberTokenBalance = await this.deployment.testToken.balanceOf(await subscriber.getAddress());
            const allowance = await this.deployment.testToken.allowance(
                await subscriber.getAddress(),
                paymentGatewayAddress
            );
            console.log(`✅ Баланс токенов подписчика: ${ethers.formatEther(subscriberTokenBalance)} TOKENS`);
            console.log(`✅ Разрешенная сумма: ${ethers.formatEther(allowance)} TOKENS`);

            // Анализируем балансы перед продлением
            await this.analyzeBalances(addresses, await this.deployment.testToken.getAddress(), "Перед продлением");

            // Выполняем продление подписки через charge()
            console.log("\n🔄 Выполнение продления подписки...");
            const chargeTx = await this.deployment.subscriptionManager
                .connect(deployer) // Используем deployer с ролью AUTOMATION_ROLE
                .charge(await subscriber.getAddress());

            const chargeReceipt = await chargeTx.wait();
            console.log("✅ Продление выполнено, газ:", chargeReceipt.gasUsed.toString());

            // Анализируем события продления
            console.log("\n📋 Анализ событий продления:");
            const renewalEvents = chargeReceipt.logs.filter((log: any) => {
                try {
                    const parsed = this.deployment.subscriptionManager.interface.parseLog(log);
                    return parsed?.name === "SubscriptionRenewed" || parsed?.name === "SubscriptionCharged";
                } catch {
                    return false;
                }
            });

            renewalEvents.forEach((event: any) => {
                const parsed = this.deployment.subscriptionManager.interface.parseLog(event);
                if (parsed && parsed.name === "SubscriptionRenewed") {
                    console.log("  🔄 SubscriptionRenewed:");
                    console.log("    📋 Subscription ID:", parsed.args.subscriptionId.toString());
                    console.log("    ⏰ Новое время окончания:", new Date(Number(parsed.args.newEndTime) * 1000).toLocaleString());
                } else if (parsed && parsed.name === "SubscriptionCharged") {
                    console.log("  💰 SubscriptionCharged:");
                    console.log("    👤 Пользователь:", parsed.args.user);
                    console.log("    💵 Сумма:", parsed.args.amount ? ethers.formatEther(parsed.args.amount) : "0", "TOKENS");
                    console.log("    ⏰ Следующее списание:", new Date(Number(parsed.args.nextBilling) * 1000).toLocaleString());
                }
            });

            // Анализируем балансы после продления
            await this.analyzeBalances(addresses, await this.deployment.testToken.getAddress(), "После продления");

            // Проверяем обновленную информацию о подписке
            const updatedSubscriptionInfo = await this.getSubscriptionInfo(await subscriber.getAddress());
            console.log("\n📊 Обновленная информация о подписке:");
            console.log("  📋 Plan Hash:", updatedSubscriptionInfo.planHash);
            console.log("  ⏰ Следующее списание:", new Date(Number(updatedSubscriptionInfo.nextBilling) * 1000).toLocaleString());

            // Проверяем, что время следующего списания обновилось
            const timeDifference = Number(updatedSubscriptionInfo.nextBilling) - Number(subscriptionInfo.nextBilling);
            console.log("  🔄 Период продления:", timeDifference, "секунд");

            if (timeDifference === plan.contractPlan.period) {
                console.log("✅ Подписка успешно продлена на корректный период");
            } else {
                console.log("⚠️ Период продления не соответствует ожидаемому");
            }

            return this.createResult(
                "Продление подписки",
                true,
                null,
                {
                    planPrice: plan.contractPlan.price ? ethers.formatEther(plan.contractPlan.price) : "0",
                    currency: "TOKENS",
                    merchant: await merchant.getAddress(),
                    subscriber: await subscriber.getAddress(),
                    gasUsed: chargeReceipt.gasUsed.toString(),
                    subscriptionId: subscriptionInfo.planHash,
                    renewalPeriod: timeDifference,
                    nextBilling: updatedSubscriptionInfo.nextBilling
                }
            );

        } catch (error: any) {
            console.log("❌ Ошибка в сценарии продления подписки:", error.message);
            return this.createResult("Продление подписки", false, error.message);
        }
    }
}

/**
 * Функция-обертка для обратной совместимости
 */
export async function testSubscriptionRenewal(
    deployment: SubscriptionDeployment,
    merchant: Signer,
    subscriber: Signer
): Promise<ScenarioResult> {
    const scenario = new SubscriptionRenewalScenario({
        deployment,
        merchant,
        subscriber
    });

    return await scenario.execute();
}
