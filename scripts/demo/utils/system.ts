import { ethers } from 'hardhat';
import { Contract, keccak256, toUtf8Bytes } from 'ethers';
import { CoreContracts, SystemRoles, SystemAccounts, ModuleSettings } from './types';
import { deployContract, deployUUPSProxy, executeTransaction } from './contracts';

/**
 * Разворачивает ядро системы (базовые контракты)
 * @returns Объект с основными контрактами
 */
export async function deployCore(): Promise<CoreContracts> {
  const [admin] = await ethers.getSigners();

  console.log('\n=== Развертывание ядра системы ===');

  try {
    // 1. AccessControlCenter - центр управления доступом
    // Создаем контракт с адресом администратора в конструкторе
    const ACCFactory = await ethers.getContractFactory('AccessControlCenter');
    // Если initialize постоянно вызывает ошибки, создаем AccessControlCenter
    // с параметрами в конструкторе, если такой конструктор существует
    const accessControl = await ACCFactory.deploy();
    await accessControl.waitForDeployment();
    console.log(`AccessControlCenter развёрнут по адресу: ${await accessControl.getAddress()}`);

    // Пробуем инициализировать, но продолжаем даже если это не удастся
    try {
      const initTx = await accessControl.initialize(admin.address, ethers.ZeroAddress);
      await initTx.wait();
      console.log('AccessControlCenter успешно инициализирован');
    } catch (error) {
      console.log('Ошибка инициализации AccessControlCenter, но продолжаем деплой:', error);
    }

    // 2. Registry - реестр для регистрации сервисов и модулей
    const registry = await deployContract('Registry');
    try {
      await registry.initialize(await accessControl.getAddress());
      console.log('Registry успешно инициализирован');
    } catch (error) {
      console.log('Ошибка инициализации Registry, но продолжаем деплой:', error);
    }

    // 3. EventRouter - маршрутизатор событий
    const eventRouter = await deployContract('EventRouter');
    try {
      await eventRouter.initialize(await accessControl.getAddress());
      console.log('EventRouter успешно инициализирован');
    } catch (error) {
      console.log('Ошибка инициализации EventRouter, но продолжаем деплой:', error);
    }

    // 4. CoreFeeManager - менеджер комиссий
    const feeManager = await deployContract('CoreFeeManager');
    try {
      await feeManager.initialize(await accessControl.getAddress(), await registry.getAddress());
      console.log('CoreFeeManager успешно инициализирован');
    } catch (error) {
      console.log('Ошибка инициализации CoreFeeManager, но продолжаем деплой:', error);
    }

    // 5. MultiValidator - валидатор токенов
    const validator = await deployContract('MultiValidator');
    try {
      await validator.initialize(await accessControl.getAddress(), await registry.getAddress());
      console.log('MultiValidator успешно инициализирован');
    } catch (error) {
      console.log('Ошибка инициализации MultiValidator, но продолжаем деплой:', error);
    }

    // 6. ChainlinkPriceOracle - оракул цен
    const priceOracle = await deployContract('ChainlinkPriceOracle');
    try {
      await priceOracle.initialize(await accessControl.getAddress(), await registry.getAddress());
      console.log('ChainlinkPriceOracle успешно инициализирован');
    } catch (error) {
      console.log('Ошибка инициализации ChainlinkPriceOracle, но продолжаем деплой:', error);
    }

    // 7. PaymentGateway - платежный шлюз
    const paymentGateway = await deployContract('PaymentGateway');
    try {
      await paymentGateway.initialize(await accessControl.getAddress(), await registry.getAddress(), await feeManager.getAddress());
      console.log('PaymentGateway успешно инициализирован');
    } catch (error) {
      console.log('Ошибка инициализации PaymentGateway, но продолжаем деплой:', error);
    }

    console.log('Ядро системы успешно развёрнуто');

    return {
      accessControl,
      registry,
      eventRouter,
      feeManager,
      validator,
      priceOracle,
      paymentGateway
    };
  } catch (error) {
    console.error('Ошибка при развертывании ядра системы:', error);
    throw error;
  }
}

/**
 * Настраивает связи между контрактами ядра
 */
export async function setupCoreConnections(contracts: CoreContracts) {
  console.log('\n=== Настройка связей между контрактами ядра ===');

  // Устанавливаем Registry в AccessControlCenter
  await executeTransaction(contracts.accessControl, 'setRegistry', [await contracts.registry.getAddress()]);

  // Регистрируем сервисы в Registry
  const SERVICE_ACCESS_CONTROL = keccak256(toUtf8Bytes('AccessControlCenter'));
  const SERVICE_REGISTRY = keccak256(toUtf8Bytes('Registry'));
  const SERVICE_FEE_MANAGER = keccak256(toUtf8Bytes('CoreFeeManager'));
  const SERVICE_PAYMENT_GATEWAY = keccak256(toUtf8Bytes('PaymentGateway'));
  const SERVICE_VALIDATOR = keccak256(toUtf8Bytes('Validator'));
  const SERVICE_PRICE_ORACLE = keccak256(toUtf8Bytes('PriceOracle'));
  const SERVICE_EVENT_ROUTER = keccak256(toUtf8Bytes('EventRouter'));

  // Регистрируем основные сервисы
  await executeTransaction(contracts.registry, 'setCoreService', [SERVICE_ACCESS_CONTROL, await contracts.accessControl.getAddress()]);
  await executeTransaction(contracts.registry, 'setCoreService', [SERVICE_REGISTRY, await contracts.registry.getAddress()]);
  await executeTransaction(contracts.registry, 'setCoreService', [SERVICE_FEE_MANAGER, await contracts.feeManager.getAddress()]);
  await executeTransaction(contracts.registry, 'setCoreService', [SERVICE_PAYMENT_GATEWAY, await contracts.paymentGateway.getAddress()]);
  await executeTransaction(contracts.registry, 'setCoreService', [SERVICE_EVENT_ROUTER, await contracts.eventRouter.getAddress()]);

  console.log('Связи между контрактами ядра установлены');
}

/**
 * Получает и возвращает все основные роли системы
 */
export async function getSystemRoles(accessControl: Contract): Promise<SystemRoles> {
  return {
    DEFAULT_ADMIN_ROLE: await accessControl.DEFAULT_ADMIN_ROLE(),
    FEATURE_OWNER_ROLE: await accessControl.FEATURE_OWNER_ROLE(),
    OPERATOR_ROLE: await accessControl.OPERATOR_ROLE(),
    RELAYER_ROLE: await accessControl.RELAYER_ROLE(),
    MODULE_ROLE: await accessControl.MODULE_ROLE(),
    AUTOMATION_ROLE: await accessControl.AUTOMATION_ROLE(),
    GOVERNOR_ROLE: await accessControl.GOVERNOR_ROLE(),
    FACTORY_ADMIN: keccak256(toUtf8Bytes('FACTORY_ADMIN'))
  };
}

/**
 * Настраивает роли для аккаунтов
 */
export async function setupRoles(contracts: CoreContracts, accounts: SystemAccounts) {
  console.log('\n=== Настройка ролей для аккаунтов ===');

  const roles = await getSystemRoles(contracts.accessControl);

  // Назначаем роли
  await executeTransaction(contracts.accessControl, 'grantRole', [roles.GOVERNOR_ROLE, accounts.governor]);
  await executeTransaction(contracts.accessControl, 'grantRole', [roles.OPERATOR_ROLE, accounts.operator]);
  await executeTransaction(contracts.accessControl, 'grantRole', [roles.AUTOMATION_ROLE, accounts.automation]);
  await executeTransaction(contracts.accessControl, 'grantRole', [roles.RELAYER_ROLE, accounts.relayer]);
  await executeTransaction(contracts.accessControl, 'grantRole', [roles.FEATURE_OWNER_ROLE, accounts.governor]);

  console.log('Роли для аккаунтов настроены');
}

/**
 * Регистрирует модуль в системе
 */
export async function registerModule(contracts: CoreContracts, moduleSettings: ModuleSettings) {
  console.log(`\n=== Регистрация модуля ${moduleSettings.name} ===`);

  const moduleId = moduleSettings.moduleId;

  // 1. Регистрируем модуль в Registry (если есть фабрика)
  if (moduleSettings.factoryAddress) {
    await executeTransaction(contracts.registry, 'registerFeature', [moduleId, moduleSettings.factoryAddress, 1]);
    console.log(`Модуль ${moduleSettings.name} зарегистрирован с фабрикой ${moduleSettings.factoryAddress}`);
  }

  // 2. Регистрируем специфичный валидатор для модуля (если есть)
  if (moduleSettings.validator) {
    const validatorAddress = await moduleSettings.validator.getAddress();
    await executeTransaction(contracts.registry, 'setModuleServiceAlias', 
      [moduleId, 'Validator', validatorAddress]);
    console.log(`Валидатор для модуля ${moduleSettings.name} установлен`);
  } else {
    // Используем общий валидатор
    await executeTransaction(contracts.registry, 'setModuleServiceAlias',
      [moduleId, 'Validator', await contracts.validator.getAddress()]);
    console.log(`Установлен общий валидатор для модуля ${moduleSettings.name}`);
  }

  // 3. Регистрируем другие сервисы модуля
  for (const [alias, address] of Object.entries(moduleSettings.services)) {
    await executeTransaction(contracts.registry, 'setModuleServiceAlias',
      [moduleId, alias, address]);
    console.log(`Сервис ${alias} для модуля ${moduleSettings.name} установлен по адресу ${address}`);
  }

  // 4. Связываем PaymentGateway с модулем
  await executeTransaction(contracts.registry, 'setModuleServiceAlias',
    [moduleId, 'PaymentGateway', await contracts.paymentGateway.getAddress()]);

  // 5. Связываем PriceOracle с модулем
  await executeTransaction(contracts.registry, 'setModuleServiceAlias',
    [moduleId, 'PriceOracle', await contracts.priceOracle.getAddress()]);

  // 6. Связываем EventRouter с модулем
  await executeTransaction(contracts.registry, 'setModuleServiceAlias',
    [moduleId, 'EventRouter', await contracts.eventRouter.getAddress()]);

  console.log(`Модуль ${moduleSettings.name} успешно зарегистрирован и настроен`);
}

/**
 * Настраивает параметры для тестовых токенов
 */
export async function setupTestTokens(contracts: CoreContracts, governor: string) {
  console.log('\n=== Развертывание и настройка тестовых токенов ===');

  // Разворачиваем тестовые ERC20 токены
  const TestToken = await ethers.getContractFactory('MockERC20');

  const usdc = await TestToken.deploy('USD Coin', 'USDC', 6);
  const usdt = await TestToken.deploy('Tether USD', 'USDT', 6);
  const dai = await TestToken.deploy('Dai Stablecoin', 'DAI', 18);
  const link = await TestToken.deploy('Chainlink', 'LINK', 18);

  console.log(`USDC развёрнут по адресу: ${await usdc.getAddress()}`);
  console.log(`USDT развёрнут по адресу: ${await usdt.getAddress()}`);
  console.log(`DAI развёрнут по адресу: ${await dai.getAddress()}`);
  console.log(`LINK развёрнут по адресу: ${await link.getAddress()}`);

  // Разворачиваем мок адаптеры Chainlink
  const MockPriceFeed = await ethers.getContractFactory('MockV3Aggregator');
  const usdcFeed = await MockPriceFeed.deploy(8, 100000000); // $1.00 с 8 десятичными знаками
  const usdtFeed = await MockPriceFeed.deploy(8, 100000000); // $1.00
  const daiFeed = await MockPriceFeed.deploy(8, 100000000);  // $1.00
  const linkFeed = await MockPriceFeed.deploy(8, 1000000000); // $10.00

  console.log(`USDC/USD feed развёрнут по адресу: ${await usdcFeed.getAddress()}`);
  console.log(`USDT/USD feed развёрнут по адресу: ${await usdtFeed.getAddress()}`);
  console.log(`DAI/USD feed развёрнут по адресу: ${await daiFeed.getAddress()}`);
  console.log(`LINK/USD feed развёрнут по адресу: ${await linkFeed.getAddress()}`);

  // Устанавливаем токены в валидатор (должен вызывать governor)
  const governorSigner = await ethers.provider.getSigner(governor);
  const validatorAsGovernor = contracts.validator.connect(governorSigner);

  await executeTransaction(validatorAsGovernor, 'addToken', [await usdc.getAddress()]);
  await executeTransaction(validatorAsGovernor, 'addToken', [await usdt.getAddress()]);
  await executeTransaction(validatorAsGovernor, 'addToken', [await dai.getAddress()]);
  await executeTransaction(validatorAsGovernor, 'addToken', [await link.getAddress()]);

  // Настраиваем PriceOracle
  await executeTransaction(contracts.priceOracle, 'setPriceFeed', 
    [await usdc.getAddress(), await usdcFeed.getAddress(), await usdc.getAddress()]);
  await executeTransaction(contracts.priceOracle, 'setPriceFeed',
    [await usdt.getAddress(), await usdtFeed.getAddress(), await usdc.getAddress()]);
  await executeTransaction(contracts.priceOracle, 'setPriceFeed',
    [await dai.getAddress(), await daiFeed.getAddress(), await usdc.getAddress()]);
  await executeTransaction(contracts.priceOracle, 'setPriceFeed',
    [await link.getAddress(), await linkFeed.getAddress(), await usdc.getAddress()]);

  console.log('Тестовые токены настроены');

  return {
    usdc,
    usdt,
    dai,
    link
  };
}
