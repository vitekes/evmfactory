/**
 * Главный файл для запуска всех сценариев подписок
 * 
 * Этот файл предоставляет единую точку входа для демонстрации
 * всех возможностей системы подписок, включая:
 * - Покупку подписок (ETH и токены)
 * - Продление подписок
 * - Отмену подписок
 * - Сбор комиссий
 * - Применение скидок
 * 
 * Использование:
 * npx hardhat run scripts/demo/subscriptions/subscriptionDemo.ts --network localhost
 */

import { ethers } from "hardhat";
import {
    deploySubscriptionContracts,
    runAllSubscriptionScenarios,
} from "./subscriptions";

/**
 * Главная функция демонстрации
 */
async function main() {
    console.log("🎬 ДЕМОНСТРАЦИЯ СИСТЕМЫ ПОДПИСОК");
    console.log("=".repeat(80));
    console.log("📅 Время запуска:", new Date().toLocaleString());

    try {
        // Получаем информацию о сети и аккаунтах
        const [deployer, merchant, subscriber] = await ethers.getSigners();
        const network = await ethers.provider.getNetwork();
        console.log("🌐 Сеть:", network.name || "неизвестно");

        console.log("\n🔧 ИНФОРМАЦИЯ О СЕТИ И АККАУНТАХ:");
        console.log("-".repeat(50));
        console.log("🌐 Сеть:", network.name, `(Chain ID: ${network.chainId})`);
        console.log("👤 Деплоер:", await deployer.getAddress());
        console.log("🏪 Мерчант:", await merchant.getAddress());
        console.log("👥 Подписчик:", await subscriber.getAddress());

        // Проверяем балансы
        const deployerBalance = await ethers.provider.getBalance(deployer.address);
        const merchantBalance = await ethers.provider.getBalance(merchant.address);
        const subscriberBalance = await ethers.provider.getBalance(subscriber.address);

        console.log("\n💰 НАЧАЛЬНЫЕ БАЛАНСЫ:");
        console.log("-".repeat(50));
        console.log("👤 Деплоер:", ethers.formatEther(deployerBalance), "ETH");
        console.log("🏪 Мерчант:", ethers.formatEther(merchantBalance), "ETH");
        console.log("👥 Подписчик:", ethers.formatEther(subscriberBalance), "ETH");

        // Проверяем минимальные балансы
        const minBalance = ethers.parseEther("1.0");
        if (deployerBalance < minBalance || merchantBalance < minBalance || subscriberBalance < minBalance) {
            console.log("\n⚠️ ПРЕДУПРЕЖДЕНИЕ: Низкие балансы!");
            console.log("   Рекомендуется иметь минимум 1 ETH на каждом аккаунте");
            console.log("   Для локальной сети используйте: npx hardhat node");
        }

        console.log("\n📦 ДЕПЛОЙ КОНТРАКТОВ ПОДПИСОК:");
        console.log("=".repeat(80));

        // Деплоим контракты подписок
        const startDeployTime = Date.now();
        const deployment = await deploySubscriptionContracts();
        const deployTime = Date.now() - startDeployTime;

        console.log("\n✅ ДЕПЛОЙ ЗАВЕРШЕН УСПЕШНО!");
        console.log("-".repeat(50));
        console.log("⏱️ Время деплоя:", deployTime, "ms");
        console.log("📋 Core System:", await deployment.core.getAddress());
        console.log("🚪 Payment Gateway:", await deployment.gateway.getAddress());
        console.log("🏭 Subscription Factory:", await deployment.subscriptionFactory.getAddress());
        console.log("📋 Subscription Manager:", await deployment.subscriptionManager.getAddress());
        console.log("🪙 Test Token:", await deployment.testToken.getAddress());
        console.log("🆔 Module ID:", deployment.moduleId);

        console.log("\n🎯 ЗАПУСК СЦЕНАРИЕВ ТЕСТИРОВАНИЯ:");
        console.log("=".repeat(80));

        // Запускаем все сценарии
        const startScenariosTime = Date.now();
        const results = await runAllSubscriptionScenarios(deployment);
        const scenariosTime = Date.now() - startScenariosTime;

        console.log("\n📈 ФИНАЛЬНАЯ СТАТИСТИКА:");
        console.log("=".repeat(80));

        const successCount = results.filter(r => r.success).length;
        const failureCount = results.length - successCount;

        console.log("📊 Общие результаты:");
        console.log(`  ✅ Успешных сценариев: ${successCount}/${results.length}`);
        console.log(`  ❌ Неудачных сценариев: ${failureCount}/${results.length}`);
        console.log(`  📊 Процент успеха: ${Math.round((successCount / results.length) * 100)}%`);
        console.log(`  ⏱️ Общее время выполнения: ${scenariosTime}ms`);
        console.log(`  ⚡ Среднее время на сценарий: ${Math.round(scenariosTime / results.length)}ms`);

        // Детальная статистика по газу
        let totalGasUsed = 0n;
        results.forEach(result => {
            if (result.success && result.details?.gasUsed) {
                const gasUsed = typeof result.details.gasUsed === 'string'
                    ? result.details.gasUsed
                    : result.details.gasUsed.toString();
                totalGasUsed += BigInt(gasUsed);
            }
        });

        if (totalGasUsed > 0n) {
            console.log(`  ⛽ Общий расход газа: ${totalGasUsed.toString()}`);
            if (successCount > 0) {
                console.log(`  💰 Средний расход газа: ${(totalGasUsed / BigInt(successCount)).toString()}`);
            }
        }

        if (successCount === results.length) {
            console.log("\n🎉 ВСЕ СЦЕНАРИИ ВЫПОЛНЕНЫ УСПЕШНО!");
            console.log("✨ Система подписок полностью функциональна");
            console.log("🚀 Готова к использованию в продакшене");
        } else {
            console.log("\n⚠️ НЕКОТОРЫЕ СЦЕНАРИИ ЗАВЕРШИЛИСЬ С ОШИБКАМИ");
            console.log("🔍 Проверьте логи выше для получения деталей");

            const failedScenarios = results.filter(r => !r.success);
            console.log("\n❌ Неудачные сценарии:");
            failedScenarios.forEach((scenario, index) => {
                console.log(`  ${index + 1}. ${scenario.name}: ${scenario.error}`);
            });
        }

        console.log("\n📋 Доступные сценарии для индивидуального запуска:");
        console.log("  • scripts/demo/subscriptions/eth-subscription.ts");
        console.log("  • scripts/demo/subscriptions/token-subscription.ts");
        console.log("  • scripts/demo/subscriptions/subscription-cancellation.ts");
        console.log("  • scripts/demo/subscriptions/subscription-renewal.ts");
        console.log("  • scripts/demo/subscriptions/commission-collection.ts");
        console.log("  • scripts/demo/subscriptions/discount-subscription.ts");

        console.log("\n📚 ДОПОЛНИТЕЛЬНАЯ ИНФОРМАЦИЯ:");
        console.log("-".repeat(50));
        console.log("📖 Документация: README.md");
        console.log("🔧 Конфигурация: hardhat.config.ts");
        console.log("📁 Контракты: contracts/modules/subscriptions/");
        console.log("🧪 Тесты: test/subscriptions/");
        console.log("📋 Сценарии: scripts/demo/subscriptions/");

        console.log("\n🏁 ДЕМОНСТРАЦИЯ ЗАВЕРШЕНА");
        console.log("=".repeat(80));
        console.log("📅 Время завершения:", new Date().toLocaleString());
        console.log("⏱️ Общее время выполнения:", Date.now() - startDeployTime, "ms");

    } catch (error: any) {
        console.log("\n❌ КРИТИЧЕСКАЯ ОШИБКА В ДЕМОНСТРАЦИИ:");
        console.log("=".repeat(80));
        console.log("🚨 Ошибка:", error.message);

        if (error.stack) {
            console.log("\n📋 Stack trace:");
            console.log(error.stack);
        }

        console.log("\n🔧 ВОЗМОЖНЫЕ РЕШЕНИЯ:");
        console.log("-".repeat(50));
        console.log("1. Убедитесь, что локальная сеть запущена: npx hardhat node");
        console.log("2. Проверьте баланс аккаунтов");
        console.log("3. Убедитесь, что все зависимости установлены: npm install");
        console.log("4. Проверьте конфигурацию сети в hardhat.config.ts");
        console.log("5. Очистите кеш: npx hardhat clean");

        process.exit(1);
    }
}

// Запускаем демонстрацию
main().catch((error) => {
    console.error("Неожиданная ошибка:", error);
    process.exit(1);
});
