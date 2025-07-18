/**
 * Главный файл для запуска всех сценариев конкурсов
 * 
 * Этот файл предоставляет единую точку входа для демонстрации
 * всех возможностей системы конкурсов, включая:
 * - Денежные конкурсы (Monetary Contest)
 * - Промо конкурсы (Promo Contest)
 * - Смешанные конкурсы (Mixed Contest)
 * 
 * Использование:
 * npx hardhat run scripts/demo/contests-demo.ts --network localhost
 */

import { ethers } from "hardhat";
import { runAllScenarios } from "./contests";
import { deployAll } from "./utils/deploy";

/**
 * Главная функция демонстрации
 */
async function main() {
    console.log("🎬 ДЕМОНСТРАЦИЯ СИСТЕМЫ КОНКУРСОВ");
    console.log("=".repeat(80));
    console.log("📅 Время запуска:", new Date().toLocaleString());

    try {
        // Получаем информацию о сети и аккаунтах
        const [deployer, organizer, participant1, participant2] = await ethers.getSigners();
        const network = await ethers.provider.getNetwork();
        console.log("🌐 Сеть:", network.name || "неизвестно");

        console.log("\n🔧 ИНФОРМАЦИЯ О СЕТИ И АККАУНТАХ:");
        console.log("-".repeat(50));
        console.log("🌐 Сеть:", network.name, `(Chain ID: ${network.chainId})`);
        console.log("👤 Деплоер:", await deployer.getAddress());
        console.log("🏆 Организатор:", await organizer.getAddress());
        console.log("👥 Участник 1:", await participant1.getAddress());
        console.log("👥 Участник 2:", await participant2.getAddress());

        // Проверяем балансы
        const deployerBalance = await ethers.provider.getBalance(deployer.address);
        const organizerBalance = await ethers.provider.getBalance(organizer.address);
        const participant1Balance = await ethers.provider.getBalance(participant1.address);
        const participant2Balance = await ethers.provider.getBalance(participant2.address);

        console.log("\n💰 НАЧАЛЬНЫЕ БАЛАНСЫ:");
        console.log("-".repeat(50));
        console.log("👤 Деплоер:", ethers.formatEther(deployerBalance), "ETH");
        console.log("🏆 Организатор:", ethers.formatEther(organizerBalance), "ETH");
        console.log("👥 Участник 1:", ethers.formatEther(participant1Balance), "ETH");
        console.log("👥 Участник 2:", ethers.formatEther(participant2Balance), "ETH");

        // Проверяем минимальные балансы
        const minBalance = ethers.parseEther("1.0");
        if (deployerBalance < minBalance || organizerBalance < minBalance ||
            participant1Balance < minBalance || participant2Balance < minBalance) {
            console.log("\n⚠️ ПРЕДУПРЕЖДЕНИЕ: Низкие балансы!");
            console.log("   Рекомендуется иметь минимум 1 ETH на каждом аккаунте");
            console.log("   Для локальной сети используйте: npx hardhat node");
        }

        console.log("\n📦 ДЕПЛОЙ КОНТРАКТОВ КОНКУРСОВ:");
        console.log("=".repeat(80));

        // Деплоим контракты
        const startDeployTime = Date.now();
        const deployment = await deployAll();
        const deployTime = Date.now() - startDeployTime;

        console.log("\n✅ ДЕПЛОЙ ЗАВЕРШЕН УСПЕШНО!");
        console.log("-".repeat(50));
        console.log("⏱️ Время деплоя:", deployTime, "ms");
        console.log("📋 Core System:", await deployment.core.getAddress());
        console.log("🚪 Payment Gateway:", await deployment.gateway.getAddress());
        console.log("🪙 Test Token:", await deployment.testToken.getAddress());

        console.log("\n🎯 ЗАПУСК СЦЕНАРИЕВ ТЕСТИРОВАНИЯ:");
        console.log("=".repeat(80));

        // Запускаем все сценарии
        const startScenariosTime = Date.now();
        const results = await runAllScenarios(deployment);
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
                totalGasUsed += BigInt(result.details.gasUsed);
            }
        });

        if (totalGasUsed > 0n) {
            console.log(`  ⛽ Общий расход газа: ${totalGasUsed.toString()}`);
            console.log(`  💰 Средний расход газа: ${(totalGasUsed / BigInt(successCount)).toString()}`);
        }

        if (successCount === results.length) {
            console.log("\n🎉 ВСЕ СЦЕНАРИИ ВЫПОЛНЕНЫ УСПЕШНО!");
            console.log("✨ Система конкурсов полностью функциональна");
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
        console.log("  • scripts/demo/contests/monetary-contest.ts");
        console.log("  • scripts/demo/contests/promo-contest.ts");
        console.log("  • scripts/demo/contests/mixed-contest.ts");

        console.log("\n📚 ДОПОЛНИТЕЛЬНАЯ ИНФОРМАЦИЯ:");
        console.log("-".repeat(50));
        console.log("📖 Документация: README.md");
        console.log("🔧 Конфигурация: hardhat.config.ts");
        console.log("📁 Контракты: contracts/modules/contests/");
        console.log("🧪 Тесты: test/contests/");
        console.log("📋 Сценарии: scripts/demo/contests/");

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
