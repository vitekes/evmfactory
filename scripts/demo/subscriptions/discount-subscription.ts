/**
 * Сценарий подписки со скидкой (Discount Subscription)
 * 
 * Демонстрирует различные механизмы применения скидок:
 * 1. Скидка через создание плана с пониженной ценой
 * 2. Скидка через альтернативный токен с лучшим курсом
 * 3. Промо-коды и временные скидки
 */

import { ethers } from "hardhat";
import { Signer } from "ethers";
import { BaseScenario, ScenarioResult, ScenarioConfig, SubscriptionDeployment } from './base-scenario';

export class DiscountSubscriptionScenario extends BaseScenario {
    constructor(config: ScenarioConfig) {
        super(config);
    }

    async execute(): Promise<ScenarioResult> {
        try {
            console.log("\n🎯 СЦЕНАРИЙ ПОДПИСКИ СО СКИДКОЙ");
            console.log("=".repeat(50));

            const { merchant, subscriber } = await this.getSigners();
            const [deployer] = await ethers.getSigners();

            // Демонстрация 1: Обычная цена vs Скидочная цена
            console.log("\n📊 ДЕМОНСТРАЦИЯ 1: ПРЯМАЯ СКИДКА НА ПЛАН");
            console.log("-".repeat(40));

            // Создаем обычный план
            const regularPlan = await this.createSubscriptionPlan(merchant, {
                id: "regular-plan",
                name: "Обычный план",
                price: ethers.parseEther("1.0"), // 1.0 ETH - обычная цена
                duration: 86400, // 1 день
                tokenAddress: ethers.ZeroAddress, // ETH
                merchant: await merchant.getAddress()
            });

            // Создаем план со скидкой 30%
            const discountedPrice = (regularPlan.contractPlan.price * BigInt(70)) / BigInt(100); // 30% скидка
            const discountPlan = await this.createSubscriptionPlan(merchant, {
                id: "discount-plan-30",
                name: "План со скидкой 30%",
                price: discountedPrice,
                duration: 86400, // 1 день
                tokenAddress: ethers.ZeroAddress, // ETH
                merchant: await merchant.getAddress()
            });

            console.log("💰 Сравнение цен:");
            console.log("  📈 Обычная цена:", ethers.formatEther(regularPlan.contractPlan.price), "ETH");
            console.log("  🎯 Цена со скидкой:", ethers.formatEther(discountPlan.contractPlan.price), "ETH");
            console.log("  💸 Экономия:", ethers.formatEther(regularPlan.contractPlan.price - discountPlan.contractPlan.price), "ETH");
            console.log("  📊 Размер скидки: 30%");

            // Анализируем балансы до подписки
            const addresses = [
                await merchant.getAddress(),
                await subscriber.getAddress()
            ];

            await this.analyzeBalances(addresses, ethers.ZeroAddress, "До подписки со скидкой");

            // Подписываемся на план со скидкой
            console.log("\n📝 Создание подписки со скидкой...");
            const subscribeValue = discountPlan.contractPlan.price + ethers.parseEther("0.05"); // Добавляем для комиссий

            const subscribeTx = await this.deployment.subscriptionManager
                .connect(subscriber)
                .subscribe(discountPlan.contractPlan, discountPlan.signature, "0x", {
                    value: subscribeValue
                });

            const subscribeReceipt = await subscribeTx.wait();
            console.log("✅ Подписка со скидкой создана, газ:", subscribeReceipt.gasUsed.toString());

            // Анализируем балансы после подписки
            await this.analyzeBalances(addresses, ethers.ZeroAddress, "После подписки со скидкой");

            // Демонстрация 2: Скидка через альтернативный токен
            console.log("\n📊 ДЕМОНСТРАЦИЯ 2: СКИДКА ЧЕРЕЗ АЛЬТЕРНАТИВНЫЙ ТОКЕН");
            console.log("-".repeat(40));

            // Создаем план в токенах с "выгодным" курсом
            const tokenPlan = await this.createSubscriptionPlan(merchant, {
                id: "token-plan",
                name: "План в токенах",
                price: ethers.parseUnits("1000", 18), // 1000 токенов
                duration: 86400, // 1 день
                tokenAddress: await this.deployment.testToken.getAddress(),
                merchant: await merchant.getAddress()
            });

            console.log("🪙 План в токенах:");
            console.log("  💰 Цена:", ethers.formatUnits(tokenPlan.contractPlan.price, 18), "токенов");
            console.log("  🏪 Мерчант:", tokenPlan.contractPlan.merchant);

            // Выдаем токены подписчику для демонстрации
            console.log("\n💰 Выдача токенов подписчику...");
            const tokenAmount = ethers.parseUnits("2000", 18); // 2000 токенов
            await this.deployment.testToken.transfer(await subscriber.getAddress(), tokenAmount);
            console.log("✅ Выдано", ethers.formatUnits(tokenAmount, 18), "токенов");

            // Анализируем балансы токенов
            await this.analyzeBalances(addresses, await this.deployment.testToken.getAddress(), "До подписки в токенах");

            // Подписываемся на план в токенах
            console.log("\n📝 Создание подписки в токенах...");

            // Сначала нужно дать разрешение на трату токенов
            const approveTx = await this.deployment.testToken
                .connect(subscriber)
                .approve(await this.deployment.gateway.getAddress(), tokenPlan.contractPlan.price);
            await approveTx.wait();
            console.log("✅ Разрешение на трату токенов выдано");

            const tokenSubscribeTx = await this.deployment.subscriptionManager
                .connect(subscriber)
                .subscribe(tokenPlan.contractPlan, tokenPlan.signature, "0x");

            const tokenSubscribeReceipt = await tokenSubscribeTx.wait();
            console.log("✅ Подписка в токенах создана, газ:", tokenSubscribeReceipt.gasUsed.toString());

            // Анализируем балансы токенов после подписки
            await this.analyzeBalances(addresses, await this.deployment.testToken.getAddress(), "После подписки в токенах");

            // Демонстрация 3: Временная скидка с ограниченным сроком
            console.log("\n📊 ДЕМОНСТРАЦИЯ 3: ВРЕМЕННАЯ СКИДКА");
            console.log("-".repeat(40));

            // Создаем план с временной скидкой (срок действия через 1 час)
            const currentTime = Math.floor(Date.now() / 1000);
            const expiryTime = currentTime + 3600; // Действует 1 час

            const tempDiscountPrice = (regularPlan.contractPlan.price * BigInt(50)) / BigInt(100); // 50% скидка
            const tempDiscountPlan = await this.createSubscriptionPlan(merchant, {
                id: "temp-discount-plan",
                name: "Временная скидка 50%",
                price: tempDiscountPrice,
                duration: 86400, // 1 день
                tokenAddress: ethers.ZeroAddress, // ETH
                merchant: await merchant.getAddress()
            });

            console.log("⏰ Временная скидка:");
            console.log("  📈 Обычная цена:", ethers.formatEther(regularPlan.contractPlan.price), "ETH");
            console.log("  🎯 Цена с временной скидкой:", ethers.formatEther(tempDiscountPlan.contractPlan.price), "ETH");
            console.log("  💸 Экономия:", ethers.formatEther(regularPlan.contractPlan.price - tempDiscountPlan.contractPlan.price), "ETH");
            console.log("  📊 Размер скидки: 50%");
            console.log("  ⏰ Действует до:", new Date(expiryTime * 1000).toLocaleString());

            // Создаем второго подписчика для временной скидки
            const [, , , subscriber2] = await ethers.getSigners();

            // Пополняем баланс второго подписчика
            const topUpTx = await deployer.sendTransaction({
                to: await subscriber2.getAddress(),
                value: ethers.parseEther("2.0")
            });
            await topUpTx.wait();

            const addresses2 = [
                await merchant.getAddress(),
                await subscriber2.getAddress()
            ];

            await this.analyzeBalances(addresses2, ethers.ZeroAddress, "До временной скидки");

            // Подписываемся на план с временной скидкой
            console.log("\n📝 Создание подписки с временной скидкой...");
            const tempSubscribeValue = tempDiscountPlan.contractPlan.price + ethers.parseEther("0.05");

            const tempSubscribeTx = await this.deployment.subscriptionManager
                .connect(subscriber2)
                .subscribe(tempDiscountPlan.contractPlan, tempDiscountPlan.signature, "0x", {
                    value: tempSubscribeValue
                });

            const tempSubscribeReceipt = await tempSubscribeTx.wait();
            console.log("✅ Подписка с временной скидкой создана, газ:", tempSubscribeReceipt.gasUsed.toString());

            await this.analyzeBalances(addresses2, ethers.ZeroAddress, "После временной скидки");

            // Демонстрация 4: Пакетная скидка (несколько подписок)
            console.log("\n📊 ДЕМОНСТРАЦИЯ 4: ПАКЕТНАЯ СКИДКА");
            console.log("-".repeat(40));

            // Создаем план с пакетной скидкой (чем больше подписок, тем больше скидка)
            const batchDiscountPrice = (regularPlan.contractPlan.price * BigInt(80)) / BigInt(100); // 20% скидка
            const batchDiscountPlan = await this.createSubscriptionPlan(merchant, {
                id: "batch-discount-plan",
                name: "Пакетная скидка 20%",
                price: batchDiscountPrice,
                duration: 86400, // 1 день
                tokenAddress: ethers.ZeroAddress, // ETH
                merchant: await merchant.getAddress()
            });

            console.log("📦 Пакетная скидка:");
            console.log("  📈 Обычная цена:", ethers.formatEther(regularPlan.contractPlan.price), "ETH");
            console.log("  🎯 Цена с пакетной скидкой:", ethers.formatEther(batchDiscountPlan.contractPlan.price), "ETH");
            console.log("  💸 Экономия на каждой подписке:", ethers.formatEther(regularPlan.contractPlan.price - batchDiscountPlan.contractPlan.price), "ETH");
            console.log("  📊 Размер скидки: 20%");

            // Создаем третьего подписчика
            const [, , , , subscriber3] = await ethers.getSigners();

            // Пополняем баланс третьего подписчика
            const topUp3Tx = await deployer.sendTransaction({
                to: await subscriber3.getAddress(),
                value: ethers.parseEther("2.0")
            });
            await topUp3Tx.wait();

            // Подписываем третьего пользователя на пакетную скидку
            const batchSubscribeValue = batchDiscountPlan.contractPlan.price + ethers.parseEther("0.05");

            const batchSubscribeTx = await this.deployment.subscriptionManager
                .connect(subscriber3)
                .subscribe(batchDiscountPlan.contractPlan, batchDiscountPlan.signature, "0x", {
                    value: batchSubscribeValue
                });

            await batchSubscribeTx.wait();
            console.log("✅ Подписка с пакетной скидкой создана");

            // Итоговая статистика по всем скидкам
            console.log("\n📈 ИТОГОВАЯ СТАТИСТИКА ПО СКИДКАМ:");
            console.log("=".repeat(50));

            const totalRegularPrice = regularPlan.contractPlan.price * BigInt(4); // 4 подписки по обычной цене
            const totalDiscountedPrice = discountPlan.contractPlan.price + tokenPlan.contractPlan.price + tempDiscountPlan.contractPlan.price + batchDiscountPlan.contractPlan.price;
            const totalSavings = totalRegularPrice - totalDiscountedPrice;

            console.log("💰 Общая экономия:");
            console.log("  📈 Обычная стоимость 4 подписок:", ethers.formatEther(totalRegularPrice), "ETH");
            console.log("  🎯 Стоимость со скидками:", ethers.formatEther(totalDiscountedPrice), "ETH");
            console.log("  💸 Общая экономия:", ethers.formatEther(totalSavings), "ETH");
            console.log("  📊 Средний размер скидки:", Math.round(Number((totalSavings * BigInt(100)) / totalRegularPrice)), "%");

            // Получаем информацию о всех подписках
            const subscriptionInfo1 = await this.getSubscriptionInfo(await subscriber.getAddress());
            const subscriptionInfo2 = await this.getSubscriptionInfo(await subscriber2.getAddress());
            const subscriptionInfo3 = await this.getSubscriptionInfo(await subscriber3.getAddress());

            return this.createResult(
                "Подписка со скидкой",
                true,
                null,
                {
                    regularPrice: ethers.formatEther(regularPlan.contractPlan.price),
                    discountedPrice: ethers.formatEther(discountPlan.contractPlan.price),
                    tempDiscountPrice: ethers.formatEther(tempDiscountPlan.contractPlan.price),
                    batchDiscountPrice: ethers.formatEther(batchDiscountPlan.contractPlan.price),
                    currency: "ETH",
                    merchant: await merchant.getAddress(),
                    subscriber: await subscriber.getAddress(),
                    totalSavings: ethers.formatEther(totalSavings),
                    averageDiscount: Math.round(Number((totalSavings * BigInt(100)) / totalRegularPrice)),
                    gasUsed: subscribeReceipt.gasUsed.toString(),
                    subscriptionIds: [
                        subscriptionInfo1.planHash,
                        subscriptionInfo2.planHash,
                        subscriptionInfo3.planHash
                    ]
                }
            );

        } catch (error: any) {
            console.log("❌ Ошибка в сценарии подписки со скидкой:", error.message);
            return this.createResult("Подписка со скидкой", false, error.message);
        }
    }
}

/**
 * Функция-обертка для обратной совместимости
 */
export async function testDiscountSubscription(
    deployment: SubscriptionDeployment,
    merchant: Signer,
    subscriber: Signer
): Promise<ScenarioResult> {
    const scenario = new DiscountSubscriptionScenario({
        deployment,
        merchant,
        subscriber
    });

    return await scenario.execute();
}
