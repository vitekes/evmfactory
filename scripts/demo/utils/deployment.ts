import { ethers } from "hardhat";
import { Contract } from "ethers";

/**
 * Деплой всех необходимых контрактов для маркетплейса
 * Правильная последовательность деплоя:
 * 1. CoreSystem
 * 2. ProcessorRegistry
 * 3. TokenFilterProcessor (и другие процессоры)
 * 4. Регистрация процессоров в registry
 * 5. PaymentOrchestrator
 * 6. Настройка процессоров в orchestrator
 * 7. PaymentGateway
 * 8. Marketplace
 * 9. Регистрация модуля в CoreSystem
 */
export async function deployMarketplaceContracts(): Promise<{
    core: Contract;
    registry: Contract;
    tokenFilter: Contract;
    feeProcessor: Contract;
    orchestrator: Contract;
    gateway: Contract;
    marketplace: Contract;
    moduleId: string;
}> {
    const [deployer] = await ethers.getSigners();
    console.log("🚀 Начинаем деплой контрактов маркетплейса...");
    console.log("👤 Деплоер:", deployer.address);

    // 1. Деплой CoreSystem
    console.log("1️⃣ Деплой CoreSystem...");
    const CoreSystem = await ethers.getContractFactory("CoreSystem");
    const core = await CoreSystem.deploy(deployer.address);
    await core.waitForDeployment();
    console.log("✅ CoreSystem задеплоен:", await core.getAddress());

    // Выдаем роль FEATURE_OWNER_ROLE деплоеру
    const featureOwner = await core.FEATURE_OWNER_ROLE();
    await core.grantRole(featureOwner, deployer.address);
    console.log("✅ Роль FEATURE_OWNER_ROLE выдана деплоеру");

    // 2. Деплой ProcessorRegistry
    console.log("2️⃣ Деплой ProcessorRegistry...");
    const ProcessorRegistry = await ethers.getContractFactory("ProcessorRegistry");
    const registry = await ProcessorRegistry.deploy();
    await registry.waitForDeployment();
    console.log("✅ ProcessorRegistry задеплоен:", await registry.getAddress());

    // 3. Деплой TokenFilterProcessor
    console.log("3️⃣ Деплой TokenFilterProcessor...");
    const TokenFilterProcessor = await ethers.getContractFactory("TokenFilterProcessor");
    const tokenFilter = await TokenFilterProcessor.deploy();
    await tokenFilter.waitForDeployment();
    console.log("✅ TokenFilterProcessor задеплоен:", await tokenFilter.getAddress());

    // 4. Деплой FeeProcessor
    console.log("4️⃣ Деплой FeeProcessor...");
    const FeeProcessor = await ethers.getContractFactory("FeeProcessor");
    const feeProcessor = await FeeProcessor.deploy(250); // 2.5% комиссия (250 базисных пунктов)
    await feeProcessor.waitForDeployment();
    console.log("✅ FeeProcessor задеплоен:", await feeProcessor.getAddress());

    // 5. Регистрация процессоров в registry
    console.log("5️⃣ Регистрация процессоров в registry...");
    await registry.registerProcessor(await tokenFilter.getAddress(), 0);
    console.log("✅ TokenFilterProcessor зарегистрирован в registry");
    await registry.registerProcessor(await feeProcessor.getAddress(), 1);
    console.log("✅ FeeProcessor зарегистрирован в registry");

    // 6. Деплой PaymentOrchestrator
    console.log("6️⃣ Деплой PaymentOrchestrator...");
    const PaymentOrchestrator = await ethers.getContractFactory("PaymentOrchestrator");
    const orchestrator = await PaymentOrchestrator.deploy(await registry.getAddress());
    await orchestrator.waitForDeployment();
    console.log("✅ PaymentOrchestrator задеплоен:", await orchestrator.getAddress());

    // 7. Деплой PaymentGateway
    console.log("7️⃣ Деплой PaymentGateway...");
    const PaymentGateway = await ethers.getContractFactory("PaymentGateway");
    const gateway = await PaymentGateway.deploy(await orchestrator.getAddress());
    await gateway.waitForDeployment();
    console.log("✅ PaymentGateway задеплоен:", await gateway.getAddress());

    // 8. Деплой Marketplace
    console.log("8️⃣ Деплой Marketplace...");
    const Marketplace = await ethers.getContractFactory("Marketplace");
    const moduleId = ethers.keccak256(ethers.toUtf8Bytes("Marketplace"));
    const marketplace = await Marketplace.deploy(await core.getAddress(), await gateway.getAddress(), moduleId);
    await marketplace.waitForDeployment();
    console.log("✅ Marketplace задеплоен:", await marketplace.getAddress());
    console.log("📋 Module ID:", moduleId);

    // 9. Регистрация модуля в CoreSystem
    console.log("9️⃣ Регистрация модуля в CoreSystem...");
    await core.registerFeature(moduleId, await marketplace.getAddress(), 1);
    await core.setService(moduleId, "PaymentGateway", await gateway.getAddress());
    console.log("✅ Модуль зарегистрирован в CoreSystem");

    // 🔟 Подготовка процессоров для последующей настройки
    console.log("🔟 Подготовка процессоров...");

    // Выдаем роль PROCESSOR_ADMIN_ROLE orchestrator'у для настройки процессоров
    const processorAdminRole = await tokenFilter.PROCESSOR_ADMIN_ROLE();
    await tokenFilter.grantRole(processorAdminRole, await orchestrator.getAddress());
    console.log("✅ Роль PROCESSOR_ADMIN_ROLE выдана orchestrator'у для TokenFilter");

    const feeProcessorAdminRole = await feeProcessor.PROCESSOR_ADMIN_ROLE();
    await feeProcessor.grantRole(feeProcessorAdminRole, await orchestrator.getAddress());
    console.log("✅ Роль PROCESSOR_ADMIN_ROLE выдана orchestrator'у для FeeProcessor");
    console.log("ℹ️ Все токены будут настроены позже в процессе полного деплоя");

    console.log("🎉 Все контракты успешно задеплоены и настроены!");

    return {
        core,
        registry,
        tokenFilter,
        feeProcessor,
        orchestrator,
        gateway,
        marketplace,
        moduleId
    };
}

/**
 * Деплой тестового ERC20 токена для демо сценариев
 * Деплоит реальный ERC20 контракт для корректной работы с SafeERC20
 */
export async function deployTestToken(name: string = "TestToken", symbol: string = "TEST"): Promise<Contract> {
    console.log(`🪙 Деплой тестового токена ${name} (${symbol})...`);

    const [deployer] = await ethers.getSigners();

    // Деплоим реальный ERC20 контракт
    const TestTokenFactory = await ethers.getContractFactory("contracts/mocks/TestToken.sol:TestToken");
    const initialSupply = ethers.parseEther("1000000");

    const testToken = await TestTokenFactory.deploy(
        name,
        symbol,
        18, // decimals
        initialSupply
    );

    await testToken.waitForDeployment();
    const tokenAddress = await testToken.getAddress();

    console.log(`✅ ${name} токен задеплоен: ${tokenAddress}`);
    console.log(`✅ Начальный запас: ${ethers.formatEther(initialSupply)} ${symbol} токенов`);

    // Проверяем баланс деплоера
    const deployerBalance = await testToken.balanceOf(deployer.address);
    console.log(`✅ Баланс деплоера: ${ethers.formatEther(deployerBalance)} ${symbol}`);

    return testToken;
}
