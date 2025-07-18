/**
 * Индексный файл для экспорта всех сценариев маркетплейса
 * 
 * Этот файл предоставляет единую точку входа для всех оптимизированных
 * сценариев маркетплейса. Каждый сценарий теперь находится в отдельном файле
 * с детальным описанием и интегрированным анализом комиссий.
 * 
 * ОПТИМИЗАЦИИ:
 * - Устранено дублирование кода через базовый класс BaseScenario
 * - Интегрирован анализ комиссий в каждый сценарий
 * - Удален отдельный сценарий проверки комиссий (testFeeCollection)
 * - Добавлены детальные пошаговые описания для каждого сценария
 * - Улучшена структура и читаемость кода
 * 
 * ДОСТУПНЫЕ СЦЕНАРИИ:
 * 1. NativeCurrencyPurchaseScenario - покупка в ETH с анализом комиссий
 * 2. TokenPurchaseScenario - покупка в ERC20 токенах с анализом комиссий
 * 3. DiscountPurchaseScenario - покупка со скидкой с анализом влияния на комиссии
 */

// Экспорт базовых типов и классов
export { BaseScenario, ScenarioResult, ScenarioConfig } from './base-scenario';

// Экспорт классов сценариев
export { NativeCurrencyPurchaseScenario } from './native-currency-purchase';
export { TokenPurchaseScenario } from './token-purchase';
export { DiscountPurchaseScenario } from './discount-purchase';

// Экспорт функций-оберток для обратной совместимости
export { testNativeCurrencyPurchase } from './native-currency-purchase';
export { testTokenPurchase } from './token-purchase';
export { testDiscountPurchase } from './discount-purchase';

// Импорты для функции runAllScenarios
import { ethers } from "hardhat";
import { DeploymentResult } from "../utils/deploy";
import { ScenarioResult } from './base-scenario';
import { testNativeCurrencyPurchase } from './native-currency-purchase';
import { testTokenPurchase } from './token-purchase';
import { testDiscountPurchase } from './discount-purchase';

/**
 * Запуск всех оптимизированных сценариев тестирования
 * 
 * ИЗМЕНЕНИЯ В ЭТОЙ ВЕРСИИ:
 * - Удален сценарий testFeeCollection (комиссии теперь анализируются в каждом сценарии)
 * - Улучшена структура отчетности
 * - Добавлена детальная статистика по каждому сценарию
 * 
 * @param deployment - результат деплоя контрактов
 * @returns массив результатов выполнения сценариев
 */
export async function runAllScenarios(deployment: DeploymentResult): Promise<ScenarioResult[]> {
    console.log("\n🎬 ЗАПУСК ВСЕХ ОПТИМИЗИРОВАННЫХ СЦЕНАРИЕВ ТЕСТИРОВАНИЯ");
    console.log("=".repeat(70));
    console.log("📋 Оптимизированные сценарии:");
    console.log("  1. 💰 Покупка в нативной валюте (ETH) + анализ комиссий");
    console.log("  2. 🪙 Покупка в токене (ERC20) + анализ комиссий");
    console.log("  3. 🏷️ Покупка со скидкой + анализ влияния на комиссии");
    console.log("=".repeat(70));
    console.log("✨ УЛУЧШЕНИЯ:");
    console.log("  • Устранено дублирование кода");
    console.log("  • Интегрирован анализ комиссий в каждый сценарий");
    console.log("  • Добавлены детальные пошаговые описания");
    console.log("  • Улучшена структура отчетности");
    console.log("=".repeat(70));

    // Получаем аккаунты для тестирования
    const [deployer, seller, buyer] = await ethers.getSigners();

    console.log("👥 Участники тестирования:");
    console.log("  Деплоер:", deployer.address);
    console.log("  Продавец:", seller.address);
    console.log("  Покупатель:", buyer.address);

    const results: ScenarioResult[] = [];
    const startTime = Date.now();

    // Запускаем все сценарии с измерением времени
    console.log("\n⏱️ Начало выполнения сценариев...");
    
    const scenario1Start = Date.now();
    results.push(await testNativeCurrencyPurchase(deployment, seller, buyer));
    const scenario1Time = Date.now() - scenario1Start;

    const scenario2Start = Date.now();
    results.push(await testTokenPurchase(deployment, seller, buyer));
    const scenario2Time = Date.now() - scenario2Start;

    const scenario3Start = Date.now();
    results.push(await testDiscountPurchase(deployment, seller, buyer));
    const scenario3Time = Date.now() - scenario3Start;

    const totalTime = Date.now() - startTime;

    // Показываем сводку результатов с улучшенной статистикой
    console.log("\n📊 СВОДКА РЕЗУЛЬТАТОВ ОПТИМИЗИРОВАННОГО ТЕСТИРОВАНИЯ");
    console.log("=".repeat(70));

    let successCount = 0;
    let totalGasUsed = 0n;
    let totalFeesCollected = 0n;

    results.forEach((result, index) => {
        const status = result.success ? "✅ УСПЕХ" : "❌ ОШИБКА";
        const timeMs = index === 0 ? scenario1Time : index === 1 ? scenario2Time : scenario3Time;
        
        console.log(`${index + 1}. ${result.name}: ${status} (${timeMs}ms)`);
        
        if (!result.success && result.error) {
            console.log(`   ❌ Ошибка: ${result.error}`);
        } else if (result.success && result.details) {
            console.log(`   💰 Цена: ${result.details.productPrice} ${result.details.currency || 'ETH'}`);
            console.log(`   💸 Продавец получил: ${result.details.sellerEarned} ${result.details.currency || 'ETH'}`);
            console.log(`   🏪 Покупатель потратил: ${result.details.buyerSpent} ${result.details.currency || 'ETH'}`);
            if (result.details.gatewayEarned) {
                console.log(`   🏛️ Gateway заработал: ${result.details.gatewayEarned} ${result.details.currency || 'ETH'}`);
            }
        }
        
        if (result.success) successCount++;
    });

    // Общая статистика
    console.log("\n📈 Общая статистика:");
    console.log(`  ✅ Успешно: ${successCount}/${results.length}`);
    console.log(`  ❌ Неудачно: ${results.length - successCount}/${results.length}`);
    console.log(`  📊 Процент успеха: ${Math.round((successCount / results.length) * 100)}%`);
    console.log(`  ⏱️ Общее время выполнения: ${totalTime}ms`);
    console.log(`  ⚡ Среднее время на сценарий: ${Math.round(totalTime / results.length)}ms`);

    // Анализ производительности
    console.log("\n⚡ Анализ производительности:");
    console.log(`  🚀 Самый быстрый сценарий: ${Math.min(scenario1Time, scenario2Time, scenario3Time)}ms`);
    console.log(`  🐌 Самый медленный сценарий: ${Math.max(scenario1Time, scenario2Time, scenario3Time)}ms`);

    // Показываем информацию об оптимизациях
    console.log("\n🎯 ДОСТИГНУТЫЕ ОПТИМИЗАЦИИ:");
    console.log("  ✅ Устранено дублирование кода между сценариями");
    console.log("  ✅ Интегрирован анализ комиссий в каждый сценарий");
    console.log("  ✅ Удален отдельный сценарий проверки комиссий");
    console.log("  ✅ Добавлены детальные описания для каждого сценария");
    console.log("  ✅ Улучшена структура и читаемость кода");
    console.log("  ✅ Создана модульная архитектура сценариев");

    if (successCount === results.length) {
        console.log("\n🎉 ВСЕ ОПТИМИЗИРОВАННЫЕ СЦЕНАРИИ ВЫПОЛНЕНЫ УСПЕШНО!");
        console.log("✨ Маркетплейс работает корректно во всех тестовых случаях");
    } else {
        console.log("\n⚠️ НЕКОТОРЫЕ СЦЕНАРИИ ЗАВЕРШИЛИСЬ С ОШИБКАМИ");
        const failedScenarios = results.filter(r => !r.success);
        console.log("\n🔍 Детали ошибок:");
        failedScenarios.forEach((scenario, index) => {
            console.log(`${index + 1}. ${scenario.name}: ${scenario.error}`);
        });
    }

    return results;
}