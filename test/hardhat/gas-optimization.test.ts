import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";

describe("Оптимизация газа: удаление дублирующих событий", function() {
  // Фикстура для развертывания контрактов
  async function deployContracts() {
    const [admin, governor] = await ethers.getSigners();

    // Разворачиваем компоненты
    const EventRouter = await ethers.getContractFactory("MockEventRouter");
    const eventRouter = await EventRouter.deploy();

    const AccessControlCenter = await ethers.getContractFactory("AccessControlCenter");
    const accessControl = await AccessControlCenter.deploy();
    await accessControl.initialize(admin.address, ethers.ZeroAddress);

    const Registry = await ethers.getContractFactory("Registry");
    const registry = await Registry.deploy();
    await registry.initialize(accessControl.address);

    // Настройка связей
    await accessControl.setRegistry(registry.address);
    await registry.setCoreService(
      ethers.encodeBytes32String("EventRouter"),
      eventRouter.address
    );

    // Назначение ролей
    await accessControl.grantRole(await accessControl.GOVERNOR_ROLE(), governor.address);
    await accessControl.grantRole(await accessControl.FEATURE_OWNER_ROLE(), admin.address);

    // Разворачиваем оптимизированный валидатор
    const MultiValidator = await ethers.getContractFactory("MultiValidator");
    const optimizedValidator = await MultiValidator.deploy();
    await optimizedValidator.initialize(accessControl.address, registry.address);

    // Разворачиваем валидатор с дублирующими событиями
    const MockMultiValidatorWithEvents = await ethers.getContractFactory("MockMultiValidatorWithEvents");
    const legacyValidator = await MockMultiValidatorWithEvents.deploy();
    await legacyValidator.initialize(accessControl.address, registry.address);

    // Подготовка тестовых токенов
    const testTokens = [];
    for (let i = 0; i < 5; i++) {
      testTokens.push(ethers.Wallet.createRandom().address);
    }

    return {
      eventRouter,
      accessControl,
      registry,
      optimizedValidator,
      legacyValidator,
      admin,
      governor,
      testTokens
    };
  }

  it("Сравнение затрат газа: добавление одного токена", async function() {
    const { optimizedValidator, legacyValidator, governor, testTokens } = await loadFixture(deployContracts);

    // Тест оптимизированной версии
    const txOptimized = await optimizedValidator.connect(governor).addToken(testTokens[0]);
    const receiptOptimized = await txOptimized.wait();
    const gasUsedOptimized = receiptOptimized!.gasUsed;

    // Тест legacy версии
    const txLegacy = await legacyValidator.connect(governor).addToken(testTokens[0]);
    const receiptLegacy = await txLegacy.wait();
    const gasUsedLegacy = receiptLegacy!.gasUsed;

    console.log(`\nДобавление одного токена:`);
    console.log(`Оптимизированная версия: ${gasUsedOptimized} газа`);
    console.log(`Legacy версия: ${gasUsedLegacy} газа`);
    console.log(`Экономия: ${gasUsedLegacy - gasUsedOptimized} газа (${(Number(gasUsedLegacy - gasUsedOptimized) / Number(gasUsedLegacy) * 100).toFixed(2)}%)`);

    expect(gasUsedOptimized).to.be.lessThan(gasUsedLegacy);
  });

  it("Сравнение затрат газа: массовое добавление токенов", async function() {
    const { optimizedValidator, legacyValidator, governor, testTokens } = await loadFixture(deployContracts);

    // Тест оптимизированной версии
    const txOptimized = await optimizedValidator.connect(governor).bulkSetToken(testTokens, true);
    const receiptOptimized = await txOptimized.wait();
    const gasUsedOptimized = receiptOptimized!.gasUsed;

    // Тест legacy версии
    const txLegacy = await legacyValidator.connect(governor).bulkSetToken(testTokens, true);
    const receiptLegacy = await txLegacy.wait();
    const gasUsedLegacy = receiptLegacy!.gasUsed;

    console.log(`\nМассовое добавление токенов (${testTokens.length} токенов):`);
    console.log(`Оптимизированная версия: ${gasUsedOptimized} газа`);
    console.log(`Legacy версия: ${gasUsedLegacy} газа`);
    console.log(`Экономия: ${gasUsedLegacy - gasUsedOptimized} газа (${(Number(gasUsedLegacy - gasUsedOptimized) / Number(gasUsedLegacy) * 100).toFixed(2)}%)`);
    console.log(`Экономия на токен: ${(gasUsedLegacy - gasUsedOptimized) / BigInt(testTokens.length)} газа`);

    expect(gasUsedOptimized).to.be.lessThan(gasUsedLegacy);
  });
});
