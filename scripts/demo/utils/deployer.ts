import { ethers } from "hardhat";
import { CONSTANTS, ROLES } from "./constants";
import { safeExecute, saveDeployment } from "./helpers";
import type { Contract, ContractFactory } from "ethers";

/** Helper to deploy an upgradeable implementation with ERC1967Proxy */
async function deployProxy(
  name: string,
  initializeArgs: any[]
): Promise<Contract> {
  const ImplFactory: ContractFactory = await ethers.getContractFactory(name);
  const impl = await ImplFactory.deploy();
  await impl.waitForDeployment();
  const implAddress = await impl.getAddress();
  const initData = ImplFactory.interface.encodeFunctionData(
    "initialize",
    initializeArgs
  );
  const Proxy = await ethers.getContractFactory("ERC1967Proxy");
  const proxy = await Proxy.deploy(implAddress, initData);
  await proxy.waitForDeployment();
  return ImplFactory.attach(await proxy.getAddress());
}


/**
 * Развертывает базовые контракты системы и возвращает их
 */
export async function deployCore(): Promise<{
  token: Contract;
  acl: Contract;
  registry: Contract;
  gateway: Contract;
  priceFeed: Contract;
  feeManager: Contract;
  validator: Contract;
  contestValidator: Contract;
}> {
  const [deployer] = await ethers.getSigners();
    console.log(`Разворачиваем базовые контракты от имени ${deployer.address}...`);
  console.log(`Деплоер: ${deployer.address}`);

  // 1. Деплой токена
  const token = await safeExecute("деплой токена", async () => {
    const Token = await ethers.getContractFactory("TestToken");
    const token = await Token.deploy("USD Coin", "USDC");
    await token.waitForDeployment();
    const tokenAddress = await token.getAddress();
    console.log(`Токен: ${tokenAddress}`);

    // Минтим токены для деплойера
    if ('mint' in token && typeof token.mint === 'function') {
      console.log(`Минтим токены для деплойера...`);
      try {
        const mintTx = await token.mint(deployer.address, ethers.parseEther("1000"));
        await mintTx.wait();
        const balance = await token.balanceOf(deployer.address);
        console.log(`Токены успешно заминчены. Баланс деплойера: ${ethers.formatEther(balance)}`);
      } catch (error) {
        console.log(`Ошибка при минтинге токенов: ${error instanceof Error ? error.message : 'Неизвестная ошибка'}`);
      }
    }

    return token;
  });

  // 2. Деплой системы контроля доступа
  const acl = await safeExecute("деплой ACL", async () => {
    const acl = await deployProxy("AccessControlCenter", [deployer.address]);
    console.log(`ACL: ${await acl.getAddress()}`);
    return acl;
  });

  // 3. Выдача ролей деплоеру
  await safeExecute("настройка ролей", async () => {
    const roleNames = {
      [ROLES.FEATURE_OWNER]: await acl.FEATURE_OWNER_ROLE(),
      [ROLES.GOVERNOR]: await acl.GOVERNOR_ROLE(),
      [ROLES.DEFAULT_ADMIN]: await acl.DEFAULT_ADMIN_ROLE(),
      [ROLES.MODULE]: await acl.MODULE_ROLE(),
      [ROLES.FACTORY_ADMIN]: CONSTANTS.FACTORY_ADMIN
    };

    // Выдаем основные роли
    for (const [roleName, roleId] of Object.entries(roleNames)) {
      if (!await acl.hasRole(roleId, deployer.address)) {
        await acl.grantRole(roleId, deployer.address);
        console.log(`Роль ${roleName} выдана: ${await acl.hasRole(roleId, deployer.address)}`);
      } else {
        console.log(`Роль ${roleName} уже выдана`);
      }
    }
  });

  // 4. Деплой реестра
  const registry = await safeExecute("деплой реестра", async () => {
    const registry = await deployProxy("Registry", [await acl.getAddress()]);
    await registry.setCoreService(
      CONSTANTS.ACCESS_SERVICE,
      await acl.getAddress()
    );
    console.log(`Реестр: ${await registry.getAddress()}`);
    return registry;
  });

  // 5. Деплой менеджера комиссий
  const feeManager = await safeExecute("деплой менеджера комиссий", async () => {
    const feeManager = await deployProxy("CoreFeeManager", [await acl.getAddress()]);
    console.log(`Менеджер комиссий: ${await feeManager.getAddress()}`);
    return feeManager;
  });

  // 6. Деплой ценового фида
  const priceFeed = await safeExecute("деплой ценового фида", async () => {
    const PriceFeed = await ethers.getContractFactory("MockPriceFeed");
    const priceFeed = await PriceFeed.deploy();
    await priceFeed.waitForDeployment();
    console.log(`Ценовой фид: ${await priceFeed.getAddress()}`);
    return priceFeed;
  });

  // 7. Деплой платежного шлюза
  const gateway = await safeExecute("деплой платежного шлюза", async () => {
    // Сначала пытаемся использовать реальный шлюз, затем fallback на мок
    let name = "PaymentGateway";
    let Gateway;
    try {
      Gateway = await ethers.getContractFactory(name);
    } catch (error) {
      console.log('PaymentGateway не найден, пробуем MockPaymentGateway...');
      name = "MockPaymentGateway";
      Gateway = await ethers.getContractFactory(name);
    }

    let gateway: Contract;
    if (name === "PaymentGateway") {
      gateway = await deployProxy(name, [
        await acl.getAddress(),
        await registry.getAddress(),
        await feeManager.getAddress(),
      ]);
    } else {
      gateway = await Gateway.deploy();
      await gateway.waitForDeployment();
      if (
        'setFeeManager' in gateway &&
        typeof (gateway as any).setFeeManager === 'function'
      ) {
        await gateway.setFeeManager(await feeManager.getAddress());
      }
    }

    console.log(`Платежный шлюз: ${await gateway.getAddress()}`);
    return gateway;
  });

  // Grant FEATURE_OWNER_ROLE to the gateway so it can collect fees
  await safeExecute("grant gateway roles", async () => {
    const featureRole = await acl.FEATURE_OWNER_ROLE();
    if (!(await acl.hasRole(featureRole, await gateway.getAddress()))) {
      await acl.grantRole(featureRole, await gateway.getAddress());
    }
  });

  // 8. Деплой и настройка токенного валидатора
  const validator = await safeExecute("деплой валидатора", async () => {
    const validator = await deployProxy("MultiValidator", [await acl.getAddress()]);
    const validatorAddress = await validator.getAddress();
    console.log(`Валидатор: ${validatorAddress}`);

    // Добавляем токен в валидатор
    try {
      const tokenAddress = await token.getAddress();
      // Проверяем метод, так как в разных версиях валидатора может быть allowed или isAllowed
      let isTokenAllowed = false;
      if ('allowed' in validator && typeof validator.allowed === 'function') {
        isTokenAllowed = await validator.allowed(tokenAddress);
      } else if ('isAllowed' in validator && typeof validator.isAllowed === 'function') {
        isTokenAllowed = await validator.isAllowed(tokenAddress);
      }

      if (!isTokenAllowed) {
        await validator.addToken(tokenAddress);
        console.log(`Токен ${tokenAddress} добавлен в валидатор`);
      } else {
        console.log(`Токен ${tokenAddress} уже разрешен в валидаторе`);
      }
    } catch (error) {
      console.log('Ошибка при добавлении токена в валидатор:', error);
    }

    return validator;
  });

  // 9. Деплой валидатора конкурсов, использующего токенный валидатор
  const contestValidator = await safeExecute("деплой валидатора конкурсов", async () => {
    const ContestValidator = await ethers.getContractFactory("ContestValidator");
    const cv = await ContestValidator.deploy(await acl.getAddress(), await validator.getAddress());
    await cv.waitForDeployment();
    console.log(`Валидатор конкурсов: ${await cv.getAddress()}`);
    return cv;
  });

  // Сохраняем данные о деплое
  const deploymentData = {
    access: await acl.getAddress(),
    registry: await registry.getAddress(),
    feeManager: await feeManager.getAddress(),
    gateway: await gateway.getAddress(),
    tokenValidator: await validator.getAddress(),
    contestValidator: await contestValidator.getAddress(),
    token: await token.getAddress(),
    priceFeed: await priceFeed.getAddress()
  };

  saveDeployment(deploymentData);

  return {
    token,
    acl,
    registry,
    gateway,
    priceFeed,
    feeManager,
    validator,
    contestValidator
  };
}

/**
 * Регистрирует модуль в реестре
 * @param registry Контракт реестра
 * @param moduleId ID модуля
 * @param factoryAddress Адрес фабрики модуля
 * @param validatorAddress Адрес валидатора токенов
 * @param gatewayAddress Адрес платежного шлюза
 */
export async function registerModule(
  registry: Contract,
  moduleId: string,
  factoryAddress: string,
  validatorAddress: string,
  gatewayAddress: string
): Promise<void> {
  await safeExecute(`регистрация модуля ${moduleId}`, async () => {
    // Проверяем, зарегистрирован ли модуль
    let isRegistered = false;
    let currentAddress = ethers.ZeroAddress;

    try {
      const [moduleAddress] = await registry.getFeature(moduleId);
      currentAddress = moduleAddress;
      isRegistered = moduleAddress !== ethers.ZeroAddress;
      console.log(`Статус модуля ${moduleId}: ${isRegistered ? 'зарегистрирован' : 'не зарегистрирован'}`);
      if (isRegistered) {
        console.log(`Текущий адрес модуля: ${currentAddress}`);
      }
    } catch (error) {
      // Проверяем, если ошибка содержит 'NotFound' - это нормально, просто модуль не зарегистрирован
      if (error instanceof Error && error.message.includes('NotFound')) {
        console.log(`Модуль ${moduleId} не найден в реестре, будет зарегистрирован`);
        isRegistered = false;
      } else {
        console.log('Ошибка при проверке регистрации модуля:', error);
      }
    }

    // Если не зарегистрирован - регистрируем
    if (!isRegistered) {
      try {
        console.log(`Регистрация модуля ${moduleId} с адресом фабрики: ${factoryAddress}`);
        await registry.registerFeature(moduleId, factoryAddress, 0);
        console.log(`Модуль ${moduleId} успешно зарегистрирован`);
      } catch (error) {
        console.error(`Ошибка при регистрации модуля ${moduleId}:`, error);
        throw error; // Пробрасываем ошибку дальше для правильной обработки
      }
    } else if (currentAddress.toLowerCase() !== factoryAddress.toLowerCase()) {
      // Обновляем адрес модуля если он изменился
      console.log(`Обновление адреса модуля с ${currentAddress} на ${factoryAddress}`);
      await registry.upgradeFeature(moduleId, factoryAddress);
      console.log(`Адрес модуля ${moduleId} обновлен`);
    } else {
      console.log(`Модуль ${moduleId} уже зарегистрирован с правильным адресом`);
    }

    // Регистрируем сервисы для модуля
    console.log(`Регистрация сервисов для модуля ${moduleId}...`);

    try {
      // Регистрация валидатора
      await registry.setModuleServiceAlias(moduleId, CONSTANTS.VALIDATOR_ALIAS, validatorAddress);
      console.log(`Валидатор (${validatorAddress}) зарегистрирован для модуля ${moduleId}`);

      // Регистрация платежного шлюза
      await registry.setModuleServiceAlias(moduleId, CONSTANTS.PAYMENT_GATEWAY_ALIAS, gatewayAddress);
      console.log(`Платежный шлюз (${gatewayAddress}) зарегистрирован для модуля ${moduleId}`);
    } catch (error) {
      console.error(`Ошибка при регистрации сервисов для модуля ${moduleId}:`, error);
      throw error; // Пробрасываем ошибку для корректной обработки выше
    }
  });
}
