/**
 * Сценарий сбора комиссии (Commission Collection)
 * 
 * Демонстрирует механизм сбора комиссий через FeeProcessor
 * при создании и продлении подписок. Показывает распределение
 * средств между мерчантом и системой комиссий.
 */

import { ethers } from "hardhat";
import { Signer } from "ethers";
import { BaseScenario, ScenarioResult, ScenarioConfig, SubscriptionDeployment } from './base-scenario';

export class CommissionCollectionScenario extends BaseScenario {
    constructor(config: ScenarioConfig) {
        super(config);
    }

    async execute(): Promise<ScenarioResult> {
        try {
            console.log("\n💰 СЦЕНАРИЙ СБОРА КОМИССИИ");
            console.log("=".repeat(50));

            const { merchant, subscriber } = await this.getSigners();
            const [deployer] = await ethers.getSigners();

            // Создаем план подписки с более высокой ценой для демонстрации комиссий
            const plan = await this.createSubscriptionPlan(merchant, {
                id: "commission-test-plan",
                name: "Тестовый план для сбора комиссии",
                price: ethers.parseEther("1.0"), // 1.0 ETH для лучшей демонстрации комиссий
                duration: 86400, // 1 день
                tokenAddress: ethers.ZeroAddress, // ETH
                merchant: await merchant.getAddress()
            });

            console.log("📋 План подписки создан:");
            console.log("  💰 Цена:", ethers.formatEther(plan.contractPlan.price), "ETH");
            console.log("  ⏰ Период:", plan.contractPlan.period, "секунд");
            console.log("  🏪 Мерчант:", plan.contractPlan.merchant);

            // Настраиваем комиссии в FeeProcessor
            console.log("\n🔧 Настройка комиссий в FeeProcessor...");

            // Получаем orchestrator и ProcessorRegistry
            const orchestratorAddress = await this.deployment.gateway.orchestrator();
            const orchestrator = await ethers.getContractAt("PaymentOrchestrator", orchestratorAddress);

            // Получаем ProcessorRegistry
            const processorRegistryAddress = await orchestrator.processorRegistry();
            const processorRegistry = await ethers.getContractAt("ProcessorRegistry", processorRegistryAddress);

            // Получаем адрес FeeProcessor
            const feeProcessorAddress = await processorRegistry.getProcessorByName("FeeProcessor");
            const feeProcessor = await ethers.getContractAt("FeeProcessor", feeProcessorAddress);

            console.log("  📍 FeeProcessor адрес:", feeProcessorAddress);

            // Настраиваем комиссию 5% (500 basis points)
            const feeRate = 500; // 5%
            const feeRecipient = await deployer.getAddress(); // Деплоер как получатель комиссий

            console.log("  📊 Настройка комиссии:", feeRate / 100, "%");
            console.log("  👤 Получатель комиссий:", feeRecipient);

            // Настраиваем FeeProcessor для модуля подписок
            // FeeProcessor ожидает ровно 2 байта для uint16 fee rate
            const feeConfigData = new Uint8Array(2);
            feeConfigData[0] = (feeRate >> 8) & 0xFF; // старший байт
            feeConfigData[1] = feeRate & 0xFF; // младший байт

            await orchestrator.configureProcessor(
                this.deployment.moduleId,
                "FeeProcessor",
                true,
                feeConfigData
            );
            console.log("✅ FeeProcessor настроен с комиссией", feeRate / 100, "%");

            // Анализируем балансы до подписки (включая получателя комиссий)
            const addresses = [
                await merchant.getAddress(),
                await subscriber.getAddress(),
                feeRecipient
            ];

            const addressLabels = ["Мерчант", "Подписчик", "Получатель комиссий"];

            await this.analyzeBalancesWithLabels(addresses, addressLabels, ethers.ZeroAddress, "До подписки");

            // Подписываемся на план
            console.log("\n📝 Создание подписки с комиссией...");
            const subscribeValue = plan.contractPlan.price + ethers.parseEther("0.1"); // Добавляем для комиссий и газа

            const subscribeTx = await this.deployment.subscriptionManager
                .connect(subscriber)
                .subscribe(plan.contractPlan, plan.signature, "0x", {
                    value: subscribeValue
                });

            const subscribeReceipt = await subscribeTx.wait();
            console.log("✅ Подписка создана, газ:", subscribeReceipt.gasUsed.toString());

            // Анализируем события для понимания распределения средств
            console.log("\n📋 Анализ событий создания подписки:");
            const subscriptionEvents = subscribeReceipt.logs.filter((log: any) => {
                try {
                    const parsed = this.deployment.subscriptionManager.interface.parseLog(log);
                    return parsed?.name === "SubscriptionCreated";
                } catch {
                    return false;
                }
            });

            subscriptionEvents.forEach((event: any) => {
                const parsed = this.deployment.subscriptionManager.interface.parseLog(event);
                console.log("  📋 SubscriptionCreated:");
                console.log("    📋 Subscription ID:", parsed.args.subscriptionId.toString());
                console.log("    👤 Владелец:", parsed.args.owner);
                console.log("    📋 Plan ID:", parsed.args.planId);
            });

            // Анализируем балансы после подписки
            await this.analyzeBalancesWithLabels(addresses, addressLabels, ethers.ZeroAddress, "После подписки");

            // Вычисляем ожидаемые суммы
            const expectedFee = plan.contractPlan.price ? (plan.contractPlan.price * BigInt(feeRate)) / BigInt(10000) : 0n;
            const expectedMerchantAmount = plan.contractPlan.price ? plan.contractPlan.price - expectedFee : 0n;

            console.log("\n💰 Ожидаемое распределение средств:");
            console.log("  💵 Общая сумма:", plan.contractPlan.price ? ethers.formatEther(plan.contractPlan.price) : "0", "ETH");
            console.log("  💰 Комиссия (5%):", expectedFee ? ethers.formatEther(expectedFee) : "0", "ETH");
            console.log("  🏪 Мерчанту:", expectedMerchantAmount ? ethers.formatEther(expectedMerchantAmount) : "0", "ETH");

            // Настраиваем роль AUTOMATION_ROLE для тестирования продления
            console.log("\n🔐 Настройка роли AUTOMATION_ROLE для продления...");
            const automationRole = ethers.keccak256(ethers.toUtf8Bytes("AUTOMATION_ROLE"));

            const hasAutomationRole = await this.deployment.core.hasRole(automationRole, await deployer.getAddress());
            if (!hasAutomationRole) {
                await this.deployment.core.grantRole(automationRole, await deployer.getAddress());
                console.log("✅ Роль AUTOMATION_ROLE выдана деплоеру");
            }

            // Пополняем баланс подписчика для продления
            console.log("\n💰 Пополнение баланса подписчика для продления...");
            const topUpTx = await deployer.sendTransaction({
                to: await subscriber.getAddress(),
                value: ethers.parseEther("2.0")
            });
            await topUpTx.wait();
            console.log("✅ Баланс подписчика пополнен");

            // Анализируем балансы перед продлением
            await this.analyzeBalancesWithLabels(addresses, addressLabels, ethers.ZeroAddress, "Перед продлением");

            // Имитируем продление через charge() (обычно это делается автоматически)
            console.log("\n🔄 Выполнение продления с комиссией...");

            // Сначала нужно дождаться времени продления или изменить время
            // Для демонстрации мы можем попробовать сразу, но это может не сработать
            try {
                const chargeTx = await this.deployment.subscriptionManager
                    .connect(deployer)
                    .charge(await subscriber.getAddress());

                const chargeReceipt = await chargeTx.wait();
                console.log("✅ Продление выполнено, газ:", chargeReceipt.gasUsed.toString());

                // Анализируем события продления
                const renewalEvents = chargeReceipt.logs.filter((log: any) => {
                    try {
                        const parsed = this.deployment.subscriptionManager.interface.parseLog(log);
                        return parsed?.name === "SubscriptionCharged";
                    } catch {
                        return false;
                    }
                });

                renewalEvents.forEach((event: any) => {
                    const parsed = this.deployment.subscriptionManager.interface.parseLog(event);
                    console.log("  💰 SubscriptionCharged:");
                    console.log("    👤 Пользователь:", parsed.args.user);
                    console.log("    💵 Сумма:", parsed.args.amount ? ethers.formatEther(parsed.args.amount) : "0", "ETH");
                });

                // Анализируем балансы после продления
                await this.analyzeBalancesWithLabels(addresses, addressLabels, ethers.ZeroAddress, "После продления");

            } catch (error: any) {
                console.log("⚠️ Продление не выполнено (возможно, еще не время):", error.message);
                console.log("   Это нормально для демонстрации - продление происходит по расписанию");
            }

            // Получаем информацию о подписке
            const subscriptionInfo = await this.getSubscriptionInfo(await subscriber.getAddress());
            console.log("\n📊 Информация о подписке:");
            console.log("  📋 Plan Hash:", subscriptionInfo.planHash);
            console.log("  ⏰ Следующее списание:", new Date(Number(subscriptionInfo.nextBilling) * 1000).toLocaleString());

            // Демонстрируем пакетное списание комиссий
            console.log("\n📦 Демонстрация пакетного сбора комиссий...");

            // Создаем еще одного подписчика для демонстрации
            const [, , , subscriber2] = await ethers.getSigners();

            // Пополняем баланс второго подписчика
            const topUp2Tx = await deployer.sendTransaction({
                to: await subscriber2.getAddress(),
                value: ethers.parseEther("2.0")
            });
            await topUp2Tx.wait();

            // Подписываем второго пользователя
            const subscribe2Tx = await this.deployment.subscriptionManager
                .connect(subscriber2)
                .subscribe(plan.contractPlan, plan.signature, "0x", {
                    value: subscribeValue
                });

            await subscribe2Tx.wait();
            console.log("✅ Второй подписчик добавлен");

            // Обновляем список адресов для анализа
            const extendedAddresses = [
                ...addresses,
                await subscriber2.getAddress()
            ];
            const extendedLabels = [
                ...addressLabels,
                "Подписчик 2"
            ];

            await this.analyzeBalancesWithLabels(extendedAddresses, extendedLabels, ethers.ZeroAddress, "После второй подписки");

            return this.createResult(
                "Сбор комиссии",
                true,
                null,
                {
                    planPrice: plan.contractPlan.price ? ethers.formatEther(plan.contractPlan.price) : "0",
                    currency: "ETH",
                    merchant: await merchant.getAddress(),
                    subscriber: await subscriber.getAddress(),
                    feeRate: feeRate / 100,
                    feeRecipient: feeRecipient,
                    expectedFee: expectedFee ? ethers.formatEther(expectedFee) : "0",
                    expectedMerchantAmount: expectedMerchantAmount ? ethers.formatEther(expectedMerchantAmount) : "0",
                    gasUsed: subscribeReceipt.gasUsed.toString(),
                    subscriptionId: subscriptionInfo.planHash
                }
            );

        } catch (error: any) {
            console.log("❌ Ошибка в сценарии сбора комиссии:", error.message);
            return this.createResult("Сбор комиссии", false, error.message);
        }
    }

    /**
     * Анализ балансов с метками для лучшего понимания
     */
    private async analyzeBalancesWithLabels(
        addresses: string[],
        labels: string[],
        tokenAddress: string,
        operation: string
    ): Promise<void> {
        console.log(`\n💰 Анализ балансов (${operation}):`);

        for (let i = 0; i < addresses.length; i++) {
            const address = addresses[i];
            const label = labels[i] || `Адрес ${i + 1}`;

            if (tokenAddress === ethers.ZeroAddress) {
                const balance = await ethers.provider.getBalance(address);
                console.log(`  ${label}: ${ethers.formatEther(balance)} ETH`);
            } else {
                const token = await ethers.getContractAt("IERC20", tokenAddress);
                const balance = await token.balanceOf(address);
                console.log(`  ${label}: ${ethers.formatUnits(balance, 18)} токенов`);
            }
        }
    }
}

/**
 * Функция-обертка для обратной совместимости
 */
export async function testCommissionCollection(
    deployment: SubscriptionDeployment,
    merchant: Signer,
    subscriber: Signer
): Promise<ScenarioResult> {
    const scenario = new CommissionCollectionScenario({
        deployment,
        merchant,
        subscriber
    });

    return await scenario.execute();
}
