/**
 * Главный файл для запуска всех сценариев маркетплейса
 *
 * Этот файл предоставляет единую точку входа для демонстрации
 * всех возможностей системы маркетплейса, включая:
 * - Покупку в нативной валюте (ETH)
 * - Покупку в токенах (ERC20)
 * - Покупку со скидкой
 * - Анализ комиссий и распределения средств
 *
 * Использование:
 * npx hardhat run scripts/demo/marketplace-demo.ts --network localhost
 */

import {runAllScenarios} from "./marketplace";
import {deployAll} from "./utils/deploy";
import {DemoRunner, DemoConfig} from "./utils/demo-runner";

/**
 * Конфигурация демонстрации маркетплейса
 */
const marketplaceConfig: DemoConfig = {
    title: "ДЕМОНСТРАЦИЯ СИСТЕМЫ МАРКЕТПЛЕЙСА",
    signerRoles: ["Деплоер", "Продавец", "Покупатель"],
    contractsSection: "ДЕПЛОЙ КОНТРАКТОВ МАРКЕТПЛЕЙСА",
    scenariosSection: "ЗАПУСК СЦЕНАРИЕВ ТЕСТИРОВАНИЯ",
    successMessage: "Система маркетплейса полностью функциональна",
    contractPaths: "contracts/modules/marketplace/",
    testPaths: "test/marketplace/",
    scenarioPaths: "scripts/demo/marketplace/",
    individualScenarios: [
        "scripts/demo/marketplace/native-currency-purchase.ts",
        "scripts/demo/marketplace/token-purchase.ts",
        "scripts/demo/marketplace/discount-purchase.ts"
    ]
};

/**
 * Главная функция демонстрации
 */
async function main() {
    const runner = new DemoRunner(marketplaceConfig);
    await runner.run(deployAll, runAllScenarios);
}

// Запускаем демонстрацию
main().catch((error) => {
    console.error("Неожиданная ошибка:", error);
    process.exit(1);
});
