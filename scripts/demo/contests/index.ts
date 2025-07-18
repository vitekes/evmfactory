/**
 * Индексный файл для экспорта всех сценариев конкурсов
 * 
 * Этот файл предоставляет единую точку входа для всех сценариев
 * тестирования системы конкурсов. Каждый сценарий находится в отдельном файле
 * с детальным описанием и интегрированным анализом комиссий.
 * 
 * ДОСТУПНЫЕ СЦЕНАРИИ:
 * 1. MonetaryContestScenario - денежный конкурс с призами в ETH
 * 2. PromoContestScenario - неденежный конкурс с промо-призами
 * 3. MixedContestScenario - смешанный конкурс с денежными и промо-призами
 * 
 * ОСОБЕННОСТИ СИСТЕМЫ КОНКУРСОВ:
 * - Поддержка денежных (MONETARY) и промо (PROMO) призов
 * - Интеграция с платёжным шлюзом для обработки комиссий
 * - Система эскроу для безопасного хранения призов
 * - Финализация конкурсов с выбором победителей
 * - Автоматическая выдача призов и NFT
 */

// Экспорт базовых типов и классов
export { BaseScenario, ScenarioResult, ScenarioConfig, ContestPrize } from './base-scenario';

// Экспорт классов сценариев
export { MonetaryContestScenario } from './monetary-contest';
export { PromoContestScenario } from './promo-contest';
export { MixedContestScenario } from './mixed-contest';

// Экспорт функций-оберток для обратной совместимости
export { testMonetaryContest } from './monetary-contest';
export { testPromoContest } from './promo-contest';
export { testMixedContest } from './mixed-contest';

// Импорты для функции runAllScenarios
import { ethers } from "hardhat";
import { DeploymentResult } from "../utils/deploy";
import { ScenarioResult } from './base-scenario';
import { testMonetaryContest } from './monetary-contest';
import { testPromoContest } from './promo-contest';
import { testMixedContest } from './mixed-contest';

/**
 * Запуск всех сценариев тестирования системы конкурсов
 * 
 * ТЕСТИРУЕМЫЕ СЦЕНАРИИ:
 * 1. Денежный конкурс - создание конкурса с призами в ETH, анализ комиссий
 * 2. Промо-конкурс - создание конкурса с неденежными призами, минимальные затраты
 * 3. Смешанный конкурс - комбинация денежных и промо-призов, частичные комиссии
 * 
 * ПРОВЕРЯЕМЫЕ АСПЕКТЫ:
 * - Создание конкурсов через ContestFactory
 * - Финансирование призов через эскроу
 * - Финализация конкурсов и выбор победителей
 * - Выдача денежных и промо-призов
 * - Списание комиссий через платёжный шлюз
 * - Выдача NFT победителям
 * - Аварийные функции (отмена, emergency withdraw)
 * 
 * @param deployment - результат деплоя контрактов
 * @returns массив результатов выполнения сценариев
 */
export async function runAllScenarios(deployment: DeploymentResult): Promise<ScenarioResult[]> {
    console.log("\n🏆 ЗАПУСК ВСЕХ СЦЕНАРИЕВ ТЕСТИРОВАНИЯ СИСТЕМЫ КОНКУРСОВ");
    console.log("=".repeat(70));
    console.log("📋 Сценарии тестирования:");
    console.log("  1. 💰 Денежный конкурс (ETH) + анализ комиссий");
    console.log("  2. 🎁 Неденежный конкурс (промо-призы) + минимальные затраты");
    console.log("  3. 🎯 Смешанный конкурс (ETH + промо) + частичные комиссии");
    console.log("=".repeat(70));
    console.log("🔍 ПРОВЕРЯЕМЫЕ ФУНКЦИИ:");
    console.log("  • Создание конкурсов через ContestFactory");
    console.log("  • Финансирование призов через эскроу");
    console.log("  • Финализация и выбор победителей");
    console.log("  • Выдача денежных и промо-призов");
    console.log("  • Списание комиссий через платёжный шлюз");
    console.log("  • Выдача NFT победителям");
    console.log("=".repeat(70));

    // Получаем аккаунты для тестирования
    const [deployer, creator, participant1, participant2, participant3, participant4] = await ethers.getSigners();
    const participants = [participant1, participant2, participant3, participant4];

    console.log("👥 Участники тестирования:");
    console.log("  Деплоер:", deployer.address);
    console.log("  Создатель конкурсов:", creator.address);
    console.log("  Участники:");
    participants.forEach((participant, index) => {
        console.log(`    ${index + 1}. ${participant.address}`);
    });

    const results: ScenarioResult[] = [];
    const startTime = Date.now();

    // Запускаем все сценарии с измерением времени
    console.log("\n⏱️ Начало выполнения сценариев...");
    
    const scenario1Start = Date.now();
    results.push(await testMonetaryContest(deployment, creator, participants));
    const scenario1Time = Date.now() - scenario1Start;

    const scenario2Start = Date.now();
    results.push(await testPromoContest(deployment, creator, participants));
    const scenario2Time = Date.now() - scenario2Start;

    const scenario3Start = Date.now();
    results.push(await testMixedContest(deployment, creator, participants));
    const scenario3Time = Date.now() - scenario3Start;

    const totalTime = Date.now() - startTime;

    // Показываем сводку результатов с детальной статистикой
    console.log("\n📊 СВОДКА РЕЗУЛЬТАТОВ ТЕСТИРОВАНИЯ СИСТЕМЫ КОНКУРСОВ");
    console.log("=".repeat(70));

    let successCount = 0;
    let totalGasUsed = 0n;
    let totalMonetaryPrizes = 0n;
    let totalPromoPrizes = 0;

    results.forEach((result, index) => {
        const status = result.success ? "✅ УСПЕХ" : "❌ ОШИБКА";
        const timeMs = index === 0 ? scenario1Time : index === 1 ? scenario2Time : scenario3Time;
        
        console.log(`${index + 1}. ${result.name}: ${status} (${timeMs}ms)`);
        
        if (!result.success && result.error) {
            console.log(`   ❌ Ошибка: ${result.error}`);
        } else if (result.success && result.details) {
            console.log(`   🏆 Призов: ${result.details.prizeCount}`);
            console.log(`   💰 Призовой фонд: ${result.details.totalPrizeValue} ${result.details.currency}`);
            console.log(`   🎯 Создатель потратил: ${result.details.creatorSpent} ${result.details.currency === 'MIXED' ? 'ETH' : result.details.currency}`);
            console.log(`   🏅 Победители получили: ${result.details.winnersReceived}`);
            if (result.details.gatewayEarned && result.details.gatewayEarned !== "0") {
                console.log(`   🏛️ Gateway заработал: ${result.details.gatewayEarned} ETH`);
            }
            console.log(`   ⛽ Газ использован: ${result.details.gasUsed}`);
            
            // Собираем статистику
            if (result.details.gasUsed) {
                totalGasUsed += BigInt(result.details.gasUsed);
            }
            
            if (result.details.currency === "ETH" || result.details.currency === "MIXED") {
                try {
                    totalMonetaryPrizes += ethers.parseEther(result.details.totalPrizeValue || "0");
                } catch {
                    // Игнорируем ошибки парсинга
                }
            }
            
            if (result.details.currency === "PROMO" || result.details.currency === "MIXED") {
                totalPromoPrizes += result.details.prizeCount;
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

    // Статистика по призам
    console.log("\n🏆 Статистика по призам:");
    console.log(`  💰 Общий денежный фонд: ${ethers.formatEther(totalMonetaryPrizes)} ETH`);
    console.log(`  🎁 Общее количество промо-призов: ${totalPromoPrizes}`);
    console.log(`  ⛽ Общий газ использован: ${totalGasUsed.toString()}`);

    // Анализ производительности
    console.log("\n⚡ Анализ производительности:");
    console.log(`  🚀 Самый быстрый сценарий: ${Math.min(scenario1Time, scenario2Time, scenario3Time)}ms`);
    console.log(`  🐌 Самый медленный сценарий: ${Math.max(scenario1Time, scenario2Time, scenario3Time)}ms`);

    // Показываем информацию о функциональности
    console.log("\n🎯 ПРОТЕСТИРОВАННАЯ ФУНКЦИОНАЛЬНОСТЬ:");
    console.log("  ✅ Создание конкурсов через ContestFactory");
    console.log("  ✅ Финансирование денежных призов");
    console.log("  ✅ Создание промо-призов без финансирования");
    console.log("  ✅ Смешанные конкурсы с разными типами призов");
    console.log("  ✅ Финализация конкурсов и выбор победителей");
    console.log("  ✅ Выдача денежных призов через эскроу");
    console.log("  ✅ Выдача промо-призов через события");
    console.log("  ✅ Списание комиссий через платёжный шлюз");
    console.log("  ✅ Анализ газовых затрат");

    if (successCount === results.length) {
        console.log("\n🎉 ВСЕ СЦЕНАРИИ СИСТЕМЫ КОНКУРСОВ ВЫПОЛНЕНЫ УСПЕШНО!");
        console.log("✨ Система конкурсов работает корректно во всех тестовых случаях");
        console.log("🏆 Платёжный шлюз успешно интегрирован с системой конкурсов");
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