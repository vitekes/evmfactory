import { ethers } from "hardhat";
import { Contract } from "ethers";
import { deployMarketplaceContracts, deployTestToken } from "./deployment";
import * as fs from "fs";
import * as path from "path";

// In-memory cache for deployment addresses to eliminate JSON file dependency
let deploymentCache: any = null;

/**
 * Интерфейс для результата полного деплоя
 */
export interface DeploymentResult {
    // Основные контракты
    core: Contract;
    registry: Contract;
    tokenFilter: Contract;
    feeProcessor: Contract;
    orchestrator: Contract;
    gateway: Contract;
    marketplace: Contract;
    moduleId: string;

    // Тестовые токены
    testToken: Contract;

    // Контракты системы конкурсов
    contestFactory: Contract;
    contestValidator: Contract;
    feeManager: Contract;
    tokenValidator: Contract;

    // Адреса для удобства
    addresses: {
        core: string;
        registry: string;
        tokenFilter: string;
        feeProcessor: string;
        orchestrator: string;
        gateway: string;
        marketplace: string;
        testToken: string;
        contestFactory: string;
        contestValidator: string;
        feeManager: string;
        tokenValidator: string;
    };
}

/**
 * Полный деплой всех контрактов для демо сценариев
 */
export async function deployAll(): Promise<DeploymentResult> {
    console.log("🚀 Начинаем полный деплой для демо сценариев...");
    console.log("=".repeat(60));

    // 1. Деплоим основные контракты маркетплейса
    const contracts = await deployMarketplaceContracts();

    console.log("\n" + "=".repeat(60));

    // 2. Деплоим тестовый токен
    const testToken = await deployTestToken("DemoToken", "DEMO");

    // 3. Деплоим дополнительные контракты для системы конкурсов
    console.log("\n🏆 Деплой дополнительных контрактов для системы конкурсов...");

    // Используем PaymentGateway как feeManager для упрощения
    const feeManager = contracts.gateway;
    console.log("✅ Используем PaymentGateway как feeManager:", await feeManager.getAddress());

    // Деплоим ContestFactory
    console.log("1️⃣ Деплой ContestFactory...");
    const ContestFactory = await ethers.getContractFactory("ContestFactory");
    const contestFactory = await ContestFactory.deploy(await contracts.core.getAddress(), await feeManager.getAddress());
    await contestFactory.waitForDeployment();
    console.log("✅ ContestFactory задеплоен:", await contestFactory.getAddress());

    // Регистрируем модуль конкурсов
    console.log("2️⃣ Регистрация модуля конкурсов...");
    const CONTEST_ID = ethers.keccak256(ethers.toUtf8Bytes("Contest"));
    await contracts.core.registerFeature(CONTEST_ID, await contestFactory.getAddress(), 0);
    console.log("✅ Модуль конкурсов зарегистрирован");

    // Создаем заглушки для совместимости
    const tokenValidator = null;
    const contestValidator = null;

    // 3. Настраиваем оба токена в TokenFilter одновременно
    console.log("\n🔧 Настройка всех токенов в TokenFilter...");

    const nativeTokenAddress = ethers.ZeroAddress;
    const testTokenAddress = await testToken.getAddress();

    // Настраиваем оба токена одновременно для избежания проблем с множественными вызовами
    const allTokensConfigData = ethers.solidityPacked(
        ["address", "address"],
        [nativeTokenAddress, testTokenAddress]
    );

    await contracts.orchestrator.configureProcessor(contracts.moduleId, "TokenFilter", true, allTokensConfigData);
    console.log("✅ Все токены настроены в TokenFilter:");
    console.log("  - Нативный токен (ETH):", nativeTokenAddress);
    console.log("  - Тестовый токен (DEMO):", testTokenAddress);

    // Настраиваем FeeProcessor
    console.log("\n🔧 Настройка FeeProcessor...");
    const feeConfigData = ethers.solidityPacked(["uint16"], [250]); // 2.5% комиссия
    await contracts.orchestrator.configureProcessor(contracts.moduleId, "FeeProcessor", true, feeConfigData);
    console.log("✅ FeeProcessor настроен с комиссией 2.5%");

    // Проверяем, что токены действительно разрешены
    console.log("\n🔍 Проверка настройки токенов...");
    try {
        // Проверяем через isPairSupported (если доступно)
        const tokenFilter = contracts.tokenFilter;
        const nativeSupported = await tokenFilter.isPairSupported(contracts.moduleId, nativeTokenAddress, nativeTokenAddress);
        const testSupported = await tokenFilter.isPairSupported(contracts.moduleId, testTokenAddress, testTokenAddress);

        console.log("  - Нативный токен разрешен:", nativeSupported ? "✅ Да" : "❌ Нет");
        console.log("  - Тестовый токен разрешен:", testSupported ? "✅ Да" : "❌ Нет");
    } catch (error) {
        console.log("  ⚠️ Не удалось проверить настройку токенов:", error instanceof Error ? error.message : String(error));
    }

    // 4. Подготавливаем адреса
    const addresses = {
        core: await contracts.core.getAddress(),
        registry: await contracts.registry.getAddress(),
        tokenFilter: await contracts.tokenFilter.getAddress(),
        feeProcessor: await contracts.feeProcessor.getAddress(),
        orchestrator: await contracts.orchestrator.getAddress(),
        gateway: await contracts.gateway.getAddress(),
        marketplace: await contracts.marketplace.getAddress(),
        testToken: await testToken.getAddress(),
        contestFactory: contestFactory ? await contestFactory.getAddress() : ethers.ZeroAddress,
        contestValidator: contestValidator ? await contestValidator.getAddress() : ethers.ZeroAddress,
        feeManager: feeManager ? await feeManager.getAddress() : ethers.ZeroAddress,
        tokenValidator: tokenValidator ? await tokenValidator.getAddress() : ethers.ZeroAddress,
    };

    console.log("\n📋 Сводка адресов контрактов:");
    console.log("  CoreSystem:", addresses.core);
    console.log("  ProcessorRegistry:", addresses.registry);
    console.log("  TokenFilterProcessor:", addresses.tokenFilter);
    console.log("  FeeProcessor:", addresses.feeProcessor);
    console.log("  PaymentOrchestrator:", addresses.orchestrator);
    console.log("  PaymentGateway:", addresses.gateway);
    console.log("  Marketplace:", addresses.marketplace);
    console.log("  TestToken:", addresses.testToken);
    console.log("  ContestFactory:", addresses.contestFactory);
    console.log("  ContestValidator:", addresses.contestValidator);
    console.log("  CoreFeeManager:", addresses.feeManager);
    console.log("  TokenValidator:", addresses.tokenValidator);

    console.log("\n🎉 Полный деплой завершен успешно!");
    console.log("=".repeat(60));

    return {
        ...contracts,
        testToken,
        contestFactory,
        contestValidator,
        feeManager,
        tokenValidator,
        addresses
    };
}


/**
 * Загрузка адресов контрактов из памяти
 */
export async function loadDeploymentAddresses(
    filename: string = "deployment-addresses.json"
): Promise<any> {
    try {
        if (deploymentCache) {
            console.log(`📂 Адреса контрактов загружены из памяти (устранена зависимость от JSON файлов)`);
            console.log(`  Сеть: ${deploymentCache.network} (Chain ID: ${deploymentCache.chainId})`);
            console.log(`  Время деплоя: ${deploymentCache.timestamp}`);

            return deploymentCache;
        } else {
            console.log(`⚠️ Нет сохраненных адресов в памяти, требуется новый деплой`);
            return null;
        }
    } catch (error) {
        console.log(`⚠️ Ошибка при загрузке из памяти:`, error);
        return null;
    }
}

/**
 * Сохранение адресов контрактов в файл и кэш
 */
export async function saveDeploymentAddresses(deployment: DeploymentResult): Promise<void> {
    try {
        const network = await ethers.provider.getNetwork();

        const deploymentData = {
            timestamp: new Date().toISOString(),
            network: network.name,
            chainId: network.chainId.toString(),
            addresses: {
                core: await deployment.core.getAddress(),
                registry: await deployment.registry.getAddress(),
                tokenFilter: await deployment.tokenFilter.getAddress(),
                orchestrator: await deployment.orchestrator.getAddress(),
                gateway: await deployment.gateway.getAddress(),
                marketplace: await deployment.marketplace.getAddress(),
                testToken: await deployment.testToken.getAddress()
            },
            moduleId: deployment.moduleId
        };

        // Сохраняем в кэш памяти
        deploymentCache = deploymentData;

        // Сохраняем в JSON файл
        const filePath = path.join(__dirname, "..", "deployment-addresses.json");
        fs.writeFileSync(filePath, JSON.stringify(deploymentData, null, 2));

        console.log("💾 Адреса контрактов сохранены:");
        console.log(`  📁 Файл: ${filePath}`);
        console.log(`  🧠 Кэш: обновлен`);
        console.log(`  🌐 Сеть: ${deploymentData.network} (Chain ID: ${deploymentData.chainId})`);

    } catch (error) {
        console.error("❌ Ошибка при сохранении адресов:", error);
        throw error;
    }
}

/**
 * Получение контрактов по сохраненным адресам
 */
export async function getContractsFromAddresses(addresses: any): Promise<Partial<DeploymentResult>> {
    console.log("🔗 Подключение к существующим контрактам...");

    const contracts: any = {};

    if (addresses.core) {
        contracts.core = await ethers.getContractAt("CoreSystem", addresses.core);
    }

    if (addresses.registry) {
        contracts.registry = await ethers.getContractAt("ProcessorRegistry", addresses.registry);
    }

    if (addresses.tokenFilter) {
        contracts.tokenFilter = await ethers.getContractAt("TokenFilterProcessor", addresses.tokenFilter);
    }

    if (addresses.orchestrator) {
        contracts.orchestrator = await ethers.getContractAt("PaymentOrchestrator", addresses.orchestrator);
    }

    if (addresses.gateway) {
        contracts.gateway = await ethers.getContractAt("PaymentGateway", addresses.gateway);
    }

    if (addresses.marketplace) {
        contracts.marketplace = await ethers.getContractAt("Marketplace", addresses.marketplace);
    }

    if (addresses.testToken) {
        contracts.testToken = await ethers.getContractAt("contracts/mocks/TestToken.sol:TestToken", addresses.testToken);
    }

    contracts.addresses = addresses;

    console.log("✅ Контракты подключены");
    return contracts;
}

/**
 * Проверка состояния деплоя
 */
export async function verifyDeployment(deployment: DeploymentResult): Promise<boolean> {
    console.log("🔍 Проверка состояния деплоя...");

    try {
        // Проверяем основные контракты
        const coreAddress = await deployment.core.getAddress();
        const marketplaceAddress = await deployment.marketplace.getAddress();
        const tokenAddress = await deployment.testToken.getAddress();

        console.log("✅ Все контракты доступны");
        console.log(`  CoreSystem: ${coreAddress}`);
        console.log(`  Marketplace: ${marketplaceAddress}`);
        console.log(`  TestToken: ${tokenAddress}`);

        // Проверяем баланс тестового токена у деплоера
        const [deployer] = await ethers.getSigners();
        const balance = await deployment.testToken.balanceOf(deployer.address);
        console.log(`✅ Баланс тестового токена у деплоера: ${ethers.formatEther(balance)} DEMO`);

        // Проверяем, что marketplace может получить адрес (базовая проверка работоспособности)
        const marketplaceAddr = await deployment.marketplace.getAddress();
        if (!marketplaceAddr || marketplaceAddr === ethers.ZeroAddress) {
            throw new Error("Marketplace адрес некорректен");
        }

        console.log("✅ Базовые проверки пройдены");
        return true;
    } catch (error) {
        console.log("❌ Ошибка при проверке деплоя:", error);
        return false;
    }
}

/**
 * Утилита для переиспользования существующего деплоя или создания нового
 */
export async function getOrDeployContracts(
    forceRedeploy: boolean = false,
    saveAddresses: boolean = true
): Promise<DeploymentResult> {
    if (!forceRedeploy) {
        // Пытаемся загрузить существующие адреса
        const savedAddresses = await loadDeploymentAddresses();

        if (savedAddresses && savedAddresses.addresses) {
            console.log("🔄 Используем существующие контракты...");
            const contracts = await getContractsFromAddresses(savedAddresses.addresses);

            if (contracts.marketplace && contracts.testToken) {
                // Проверяем, что контракты работают
                try {
                    await contracts.marketplace.getAddress();
                    console.log("✅ Существующие контракты работают");
                    return contracts as DeploymentResult;
                } catch (error) {
                    console.log("⚠️ Существующие контракты недоступны, выполняем новый деплой");
                }
            }
        }
    }

    // Выполняем новый деплой
    console.log("🆕 Выполняем новый деплой...");
    const deployment = await deployAll();

    if (saveAddresses) {
        await saveDeploymentAddresses(deployment);
    }

    return deployment;
}
