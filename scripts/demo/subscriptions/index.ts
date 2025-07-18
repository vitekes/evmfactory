/**
 * Индексный файл для экспорта всех сценариев подписок
 * 
 * Этот файл предоставляет единую точку входа для всех сценариев
 * системы подписок. Каждый сценарий находится в отдельном файле
 * с детальным описанием и интегрированным анализом балансов.
 * 
 * ДОСТУПНЫЕ СЦЕНАРИИ:
 * 1. EthSubscriptionScenario - подписка в ETH с анализом балансов
 * 2. TokenSubscriptionScenario - подписка в ERC20 токенах с анализом балансов
 * 3. SubscriptionCancellationScenario - отмена подписки с проверкой статуса
 * 
 * ИСПРАВЛЕНИЯ:
 * - Исправлена критическая ошибка с ролями и регистрацией модулей
 * - Добавлена правильная настройка SUBSCRIPTION_MODULE_ID
 * - Улучшена обработка ошибок и логирование
 */

// Экспорт базовых типов и классов
export { BaseScenario, ScenarioResult, ScenarioConfig, SubscriptionDeployment, SubscriptionPlan, ContractPlan } from './base-scenario';

// Экспорт утилит деплоя
export { deploySubscriptionContracts } from '../utils/subscriptions';

// Экспорт классов сценариев
export { EthSubscriptionScenario } from './eth-subscription';
export { TokenSubscriptionScenario } from './token-subscription';
export { SubscriptionCancellationScenario } from './subscription-cancellation';
export { SubscriptionRenewalScenario } from './subscription-renewal';
export { CommissionCollectionScenario } from './commission-collection';
export { DiscountSubscriptionScenario } from './discount-subscription';

// Экспорт функций-оберток для обратной совместимости
export { testEthSubscription } from './eth-subscription';
export { testTokenSubscription } from './token-subscription';
export { testSubscriptionCancellation } from './subscription-cancellation';
export { testSubscriptionRenewal } from './subscription-renewal';
export { testCommissionCollection } from './commission-collection';
export { testDiscountSubscription } from './discount-subscription';

// Импорты для функции runAllScenarios
import { ethers } from "hardhat";
import { SubscriptionDeployment, ScenarioResult } from './base-scenario';
import { testEthSubscription } from './eth-subscription';
import { testTokenSubscription } from './token-subscription';
import { testSubscriptionCancellation } from './subscription-cancellation';
import { testSubscriptionRenewal } from './subscription-renewal';
import { testCommissionCollection } from './commission-collection';
import { testDiscountSubscription } from './discount-subscription';

/**
 * Запуск всех сценариев тестирования подписок
 * 
 * ИСПРАВЛЕНИЯ В ЭТОЙ ВЕРСИИ:
 * - Исправлена критическая ошибка с ролями FEATURE_OWNER_ROLE
 * - Добавлена правильная регистрация SUBSCRIPTION_MODULE_ID
 * - Улучшена структура отчетности
 * - Добавлена детальная статистика по каждому сценарию
 * 
 * @param deployment - результат деплоя контрактов подписок
 * @returns массив результатов выполнения сценариев
 */
export async function runAllSubscriptionScenarios(deployment: SubscriptionDeployment): Promise<ScenarioResult[]> {
    console.log("\n🎬 ЗАПУСК ВСЕХ СЦЕНАРИЕВ ТЕСТИРОВАНИЯ ПОДПИСОК");
    console.log("=".repeat(70));
    console.log("📋 Доступные сценарии:");
    console.log("  1. 💰 Подписка в нативной валюте (ETH) + анализ балансов");
    console.log("  2. 🪙 Подписка в токенах (ERC20) + анализ балансов");
    console.log("  3. ❌ Отмена подписки + проверка статуса");
    console.log("  4. 🔄 Продление подписки + автоматическое списание");
    console.log("  5. 💰 Сбор комиссии + распределение средств");
    console.log("  6. 🎯 Подписка со скидкой + различные типы скидок");
    console.log("=".repeat(70));

    // Получаем аккаунты для тестирования
    const [deployer, merchant, subscriber] = await ethers.getSigners();

    console.log("👥 Участники тестирования:");
    console.log("  Деплоер:", await deployer.getAddress());
    console.log("  Мерчант:", await merchant.getAddress());
    console.log("  Подписчик:", await subscriber.getAddress());

    const results: ScenarioResult[] = [];
    const startTime = Date.now();

    // Запускаем все сценарии с измерением времени
    console.log("\n⏱️ Начало выполнения сценариев...");

    const scenario1Start = Date.now();
    results.push(await testEthSubscription(deployment, merchant, subscriber));
    const scenario1Time = Date.now() - scenario1Start;

    const scenario2Start = Date.now();
    results.push(await testTokenSubscription(deployment, merchant, subscriber));
    const scenario2Time = Date.now() - scenario2Start;

    const scenario3Start = Date.now();
    results.push(await testSubscriptionCancellation(deployment, merchant, subscriber));
    const scenario3Time = Date.now() - scenario3Start;

    const scenario4Start = Date.now();
    results.push(await testSubscriptionRenewal(deployment, merchant, subscriber));
    const scenario4Time = Date.now() - scenario4Start;

    const scenario5Start = Date.now();
    results.push(await testCommissionCollection(deployment, merchant, subscriber));
    const scenario5Time = Date.now() - scenario5Start;

    const scenario6Start = Date.now();
    results.push(await testDiscountSubscription(deployment, merchant, subscriber));
    const scenario6Time = Date.now() - scenario6Start;

    const totalTime = Date.now() - startTime;

    // Показываем сводку результатов с улучшенной статистикой
    console.log("\n📊 СВОДКА РЕЗУЛЬТАТОВ ТЕСТИРОВАНИЯ ПОДПИСОК");
    console.log("=".repeat(70));

    let successCount = 0;
    let totalGasUsed = 0n;

    results.forEach((result, index) => {
        const status = result.success ? "✅ УСПЕХ" : "❌ ОШИБКА";
        const timeMs = index === 0 ? scenario1Time : 
                      index === 1 ? scenario2Time : 
                      index === 2 ? scenario3Time :
                      index === 3 ? scenario4Time :
                      index === 4 ? scenario5Time : scenario6Time;

        console.log(`${index + 1}. ${result.name}: ${status} (${timeMs}ms)`);

        if (!result.success && result.error) {
            console.log(`   ❌ Ошибка: ${result.error}`);
        } else if (result.success && result.details) {
            if (result.details.planPrice) {
                console.log(`   💰 Цена плана: ${result.details.planPrice} ${result.details.currency || 'ETH'}`);
            }
            if (result.details.merchant) {
                console.log(`   🏪 Мерчант: ${result.details.merchant}`);
            }
            if (result.details.subscriber) {
                console.log(`   👤 Подписчик: ${result.details.subscriber}`);
            }
            if (result.details.gasUsed) {
                console.log(`   ⛽ Газ использован: ${result.details.gasUsed}`);
            }
            if (result.details.subscriptionId) {
                console.log(`   📋 ID подписки: ${result.details.subscriptionId}`);
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
    const scenarioTimes = [scenario1Time, scenario2Time, scenario3Time, scenario4Time, scenario5Time, scenario6Time];
    console.log("\n⚡ Анализ производительности:");
    console.log(`  🚀 Самый быстрый сценарий: ${Math.min(...scenarioTimes)}ms`);
    console.log(`  🐌 Самый медленный сценарий: ${Math.max(...scenarioTimes)}ms`);

    if (successCount === results.length) {
        console.log("\n🎉 ВСЕ СЦЕНАРИИ ПОДПИСОК ВЫПОЛНЕНЫ УСПЕШНО!");
        console.log("✨ Система подписок работает корректно во всех тестовых случаях");
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
