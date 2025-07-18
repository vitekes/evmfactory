/**
 * Утилиты для деплоя контрактов подписок
 * 
 * Вынесены из scripts/demo/subscriptions/deployment.ts для переиспользования
 * в различных демо-сценариях
 */

import { ethers } from "hardhat";
import { Signer, Contract } from "ethers";
import { getOrDeployContracts } from "./deploy";

export interface SubscriptionDeployment {
    core: Contract;
    gateway: Contract;
    subscriptionFactory: Contract;
    subscriptionManager: Contract;
    testToken: Contract;
    moduleId: string;
}

/**
 * Деплой контрактов подписок с правильной настройкой ролей
 */
export async function deploySubscriptionContracts(): Promise<SubscriptionDeployment> {
    console.log("🚀 Деплой контрактов системы подписок...");

    const [deployer] = await ethers.getSigners();
    console.log("👤 Деплоер:", deployer.address);

    // Получаем базовые контракты
    const baseDeployment = await getOrDeployContracts();
    console.log("✅ Базовые контракты получены");

    // Вычисляем SUBSCRIPTION_MODULE_ID
    const subscriptionModuleId = ethers.keccak256(ethers.toUtf8Bytes("SubscriptionManager"));
    console.log("📋 SUBSCRIPTION_MODULE_ID:", subscriptionModuleId);

    // Проверяем и регистрируем модуль подписок в CoreSystem
    console.log("🔧 Регистрация модуля подписок в CoreSystem...");
    try {
        // Проверяем, зарегистрирован ли модуль
        await baseDeployment.core.getFeature(subscriptionModuleId);
        console.log("✅ Модуль подписок уже зарегистрирован");
    } catch {
        // Модуль не зарегистрирован, регистрируем его
        console.log("📝 Регистрация нового модуля подписок...");
        await baseDeployment.core.registerFeature(
            subscriptionModuleId,
            deployer.address, // Временный адрес, будет обновлен после создания фабрики
            1 // версия
        );
        console.log("✅ Модуль подписок зарегистрирован");
    }

    // Деплоим SubscriptionManagerFactory
    const subscriptionFactory = await deploySubscriptionManagerFactory(baseDeployment);

    // Обновляем адрес модуля в CoreSystem на адрес фабрики
    console.log("🔄 Обновление адреса модуля в CoreSystem...");
    await baseDeployment.core.upgradeFeature(subscriptionModuleId, await subscriptionFactory.getAddress());
    console.log("✅ Адрес модуля обновлен на фабрику");

    // Настраиваем роли
    await setupSubscriptionRoles(baseDeployment.core, subscriptionFactory, deployer);

    // Создаем SubscriptionManager через фабрику
    const subscriptionManager = await createSubscriptionManager(subscriptionFactory);

    // Получаем MODULE_ID
    const moduleId = await subscriptionManager.MODULE_ID();
    console.log("📋 Module ID:", moduleId);

    // Настраиваем сервисы и процессоры
    await setupSubscriptionServices(baseDeployment, moduleId);
    await setupSubscriptionProcessors(baseDeployment, moduleId);
    await setupSubscriptionTokens(baseDeployment, moduleId);

    console.log("🎉 Деплой контрактов подписок завершен успешно!");

    return {
        core: baseDeployment.core,
        gateway: baseDeployment.gateway,
        subscriptionFactory,
        subscriptionManager,
        testToken: baseDeployment.testToken,
        moduleId
    };
}

/**
 * Деплой SubscriptionManagerFactory
 */
export async function deploySubscriptionManagerFactory(baseDeployment: any): Promise<Contract> {
    console.log("📦 Деплой SubscriptionManagerFactory...");
    const SubscriptionManagerFactory = await ethers.getContractFactory("SubscriptionManagerFactory");
    const subscriptionFactory = await SubscriptionManagerFactory.deploy(
        await baseDeployment.core.getAddress(),
        await baseDeployment.gateway.getAddress()
    );
    await subscriptionFactory.waitForDeployment();
    console.log("✅ SubscriptionManagerFactory задеплоен:", await subscriptionFactory.getAddress());
    return subscriptionFactory;
}

/**
 * Настройка ролей для системы подписок
 */
export async function setupSubscriptionRoles(core: Contract, subscriptionFactory: Contract, deployer: Signer): Promise<void> {
    console.log("🔐 Настройка ролей для системы подписок...");
    
    const featureOwnerRole = ethers.keccak256(ethers.toUtf8Bytes("FEATURE_OWNER_ROLE"));
    const deployerAddress = await deployer.getAddress();
    const factoryAddress = await subscriptionFactory.getAddress();

    // Убеждаемся, что у деплоера есть роль FEATURE_OWNER_ROLE
    const deployerHasRole = await core.hasRole(featureOwnerRole, deployerAddress);
    if (!deployerHasRole) {
        console.log("⚠️ Выдача роли FEATURE_OWNER_ROLE деплоеру...");
        await core.grantRole(featureOwnerRole, deployerAddress);
        console.log("✅ Роль FEATURE_OWNER_ROLE выдана деплоеру");
    } else {
        console.log("✅ Роль FEATURE_OWNER_ROLE уже есть у деплоера");
    }

    // Выдаем роль FEATURE_OWNER_ROLE фабрике
    const factoryHasRole = await core.hasRole(featureOwnerRole, factoryAddress);
    if (!factoryHasRole) {
        console.log("⚠️ Выдача роли FEATURE_OWNER_ROLE фабрике...");
        await core.grantRole(featureOwnerRole, factoryAddress);
        console.log("✅ Роль FEATURE_OWNER_ROLE выдана фабрике");
    } else {
        console.log("✅ Роль FEATURE_OWNER_ROLE уже есть у фабрики");
    }
}

/**
 * Создание SubscriptionManager через фабрику
 */
export async function createSubscriptionManager(subscriptionFactory: Contract): Promise<Contract> {
    console.log("🏭 Создание SubscriptionManager через фабрику...");
    const tx = await subscriptionFactory.createSubscriptionManager();
    const receipt = await tx.wait();

    // Получаем адрес созданного SubscriptionManager из события
    const event = receipt.logs.find((log: any) => {
        try {
            const parsed = subscriptionFactory.interface.parseLog(log);
            return parsed?.name === "SubscriptionManagerCreated";
        } catch {
            return false;
        }
    });

    if (!event) {
        throw new Error("Не удалось найти событие SubscriptionManagerCreated");
    }

    const parsedEvent = subscriptionFactory.interface.parseLog(event);
    const subscriptionManagerAddress = parsedEvent.args.subManager;

    console.log("✅ SubscriptionManager создан:", subscriptionManagerAddress);

    // Подключаемся к созданному SubscriptionManager
    return await ethers.getContractAt("SubscriptionManager", subscriptionManagerAddress);
}

/**
 * Настройка сервисов для SubscriptionManager
 */
export async function setupSubscriptionServices(baseDeployment: any, moduleId: string): Promise<void> {
    console.log("🔧 Настройка сервисов для SubscriptionManager...");
    
    // Настраиваем PaymentGateway
    await baseDeployment.core.setService(
        moduleId,
        "PaymentGateway",
        await baseDeployment.gateway.getAddress()
    );
    console.log("✅ PaymentGateway настроен для SubscriptionManager");
}

/**
 * Настройка процессоров для модуля подписок
 */
export async function setupSubscriptionProcessors(baseDeployment: any, moduleId: string): Promise<void> {
    console.log("🔧 Настройка процессоров для модуля подписок...");

    // Получаем orchestrator из базового деплоя
    const orchestratorAddress = await baseDeployment.gateway.orchestrator();
    const orchestrator = await ethers.getContractAt("PaymentOrchestrator", orchestratorAddress);

    // Настраиваем TokenFilter для модуля подписок
    await orchestrator.configureProcessor(
        moduleId,
        "TokenFilter",
        true,
        "0x"
    );
    console.log("✅ TokenFilter настроен для модуля подписок");

    // Настраиваем FeeProcessor для модуля подписок
    await orchestrator.configureProcessor(
        moduleId,
        "FeeProcessor", 
        true,
        "0x"
    );
    console.log("✅ FeeProcessor настроен для модуля подписок");
}

/**
 * Настройка токенов для модуля подписок
 */
export async function setupSubscriptionTokens(baseDeployment: any, moduleId: string): Promise<void> {
    console.log("🔧 Настройка токенов для модуля подписок...");

    const orchestratorAddress = await baseDeployment.gateway.orchestrator();
    const orchestrator = await ethers.getContractAt("PaymentOrchestrator", orchestratorAddress);

    // Создаем configData с адресами токенов (по 20 байт каждый)
    const ethAddress = ethers.ZeroAddress;
    const testTokenAddress = await baseDeployment.testToken.getAddress();

    // Упаковываем адреса в configData (каждый адрес 20 байт)
    const configData = ethers.concat([
        ethers.getBytes(ethAddress).slice(-20), // ETH address (20 bytes)
        ethers.getBytes(testTokenAddress).slice(-20) // Test token address (20 bytes)
    ]);

    // Настраиваем TokenFilter с токенами для модуля подписок
    await orchestrator.configureProcessor(
        moduleId,
        "TokenFilter",
        true,
        configData
    );
    console.log("✅ Токены настроены для модуля подписок (ETH и тестовый токен)");
}

/**
 * Быстрый деплой для тестирования (без детального логирования)
 */
export async function deploySubscriptionContractsQuick(): Promise<SubscriptionDeployment> {
    const [deployer] = await ethers.getSigners();
    const baseDeployment = await getOrDeployContracts();
    
    const subscriptionModuleId = ethers.keccak256(ethers.toUtf8Bytes("SubscriptionManager"));
    
    try {
        await baseDeployment.core.getFeature(subscriptionModuleId);
    } catch {
        await baseDeployment.core.registerFeature(subscriptionModuleId, deployer.address, 1);
    }

    const subscriptionFactory = await deploySubscriptionManagerFactory(baseDeployment);
    await baseDeployment.core.upgradeFeature(subscriptionModuleId, await subscriptionFactory.getAddress());
    await setupSubscriptionRoles(baseDeployment.core, subscriptionFactory, deployer);
    
    const subscriptionManager = await createSubscriptionManager(subscriptionFactory);
    const moduleId = await subscriptionManager.MODULE_ID();
    
    await setupSubscriptionServices(baseDeployment, moduleId);
    await setupSubscriptionProcessors(baseDeployment, moduleId);
    await setupSubscriptionTokens(baseDeployment, moduleId);

    return {
        core: baseDeployment.core,
        gateway: baseDeployment.gateway,
        subscriptionFactory,
        subscriptionManager,
        testToken: baseDeployment.testToken,
        moduleId
    };
}