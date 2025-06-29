import { ethers } from "hardhat";
import { CONSTANTS, safeExecute as execSafe } from "./helper";
import type { Contract } from "ethers";

// Константы
const RETRY_TIMEOUT = 2000;
const MAX_RETRIES = 3;

// Используем константы из helper.ts
const IDS = {
  // Строковые алиасы для сервисов
  VALIDATOR_ALIAS: "Validator",
  PAYMENT_GATEWAY_ALIAS: "PaymentGateway",

  // bytes32 константы для core сервисов и ID модулей
  ACL_SERVICE: CONSTANTS.ACCESS_SERVICE,
  MARKETPLACE_ID: CONSTANTS.MARKETPLACE_ID,
  FACTORY_ADMIN: CONSTANTS.FACTORY_ADMIN
};

// Утилита повторения запросов при ошибках сети
export async function withRetry<T>(fn: () => Promise<T>, onErrorCallback?: (error: Error, attempt: number) => Promise<void>): Promise<T> {
  let lastError: Error = new Error('Неизвестная ошибка');
  for (let i = 0; i < MAX_RETRIES; i++) {
    try {
      return await fn();
    } catch (error) {
      const typedError = error as Error;
      console.warn(`Попытка ${i + 1} не удалась, повторяем через ${RETRY_TIMEOUT}мс...`);
      lastError = typedError;
      if (onErrorCallback) await onErrorCallback(typedError, i);
      await new Promise(resolve => setTimeout(resolve, RETRY_TIMEOUT));
    }
  }
  console.error('Все попытки исчерпаны, последняя ошибка:', lastError);
  return Promise.reject(lastError);
}

// Вспомогательные функции
async function getModuleServiceByAlias(registry: Contract, moduleId: string, serviceAlias: string): Promise<string> {
  console.log(`Получение сервиса '${serviceAlias}' для модуля ${moduleId}...`);

  try {
    // Проверяем, существует ли модуль
    try {
      const [moduleAddress] = await registry.getFeature(moduleId);
      if (moduleAddress === ethers.ZeroAddress) {
        console.log(`Модуль с ID ${moduleId} не зарегистрирован в реестре`);
        return ethers.ZeroAddress;
      }
      console.log(`Модуль ${moduleId} найден по адресу ${moduleAddress}`);
    } catch (e) {
      console.log(`Ошибка при проверке модуля ${moduleId}:`, e);
      // Продолжаем, так как модуль может быть зарегистрирован позже
    }

    let result = ethers.ZeroAddress;
    let successMethod = '';

    // Пробуем все возможные методы получения сервиса
    const methods = [
      { name: 'getModuleServiceByAlias(bytes32,string)', bytesType: false },
      { name: 'getModuleService(bytes32,string)', bytesType: false },
      { name: 'getModuleService(bytes32,bytes32)', bytesType: true }
    ];

    for (const method of methods) {
      try {
        console.log(`Пробуем метод ${method.name}...`);
        if (!method.bytesType) {
          // Метод принимает строку
          const res = await registry.getFunction(method.name).staticCall(moduleId, serviceAlias);
          if (res && res !== ethers.ZeroAddress) {
            result = res;
            successMethod = method.name;
            break;
          }
        } else {
          // Метод принимает bytes32
          // Конвертируем строку в bytes32 если нужно
          const aliasBytes32 = ethers.keccak256(ethers.toUtf8Bytes(serviceAlias));
          const res = await registry.getFunction(method.name).staticCall(moduleId, aliasBytes32);
          if (res && res !== ethers.ZeroAddress) {
            result = res;
            successMethod = method.name;
            break;
          }
        }
      } catch (methodError) {
        const err = methodError as Error;
        console.log(`Метод ${method.name} не сработал:`, err.message);
        // Продолжаем со следующим методом
      }
    }

    if (result !== ethers.ZeroAddress) {
      console.log(`Успешно получен сервис '${serviceAlias}' через метод ${successMethod}: ${result}`);
    } else {
      console.log(`Не удалось получить сервис '${serviceAlias}' для модуля ${moduleId}`);
    }

    return result;
  } catch (error) {
    console.log(`Общая ошибка при получении сервиса '${serviceAlias}' для модуля ${moduleId}:`, error);
    return ethers.ZeroAddress;
  }
}

// Используем safeExecute из helper.ts (импортируется как execSafe)

// Глобальное состояние
let marketplaceAddress = "";

/**
 * Настройка демонстрационного окружения: разворачивает контракты и настраивает маркетплейс.
 */
async function setupDemoEnvironment(): Promise<{
  marketplaceFactory: Contract;
  token: Contract;
  priceFeed: Contract;
  registry: Contract;
  gateway: Contract;
  acl: Contract;
  marketplaceAddress: string;
  validator: Contract;
}> {
  const [deployer] = await ethers.getSigners();
  // Переменная для хранения адреса созданного маркетплейса
  let mpAddress;

  // 1. Деплой токена
  const token = await execSafe("деплой токена", async () => {
    const Token = await ethers.getContractFactory("TestToken");
    const token = await Token.deploy("USD Coin", "USDC");
    await token.waitForDeployment();
    console.log(`Токен: ${await token.getAddress()}`);
    return token;
  });

  // 2. Деплой ACL
  const acl = await execSafe("деплой ACL", async () => {
    const ACL = await ethers.getContractFactory("AccessControlCenter");
    const acl = await ACL.deploy();
    await acl.waitForDeployment();
    console.log(`ACL: ${await acl.getAddress()}`);
    await acl.initialize(deployer.address);
    return acl;
  });

  // 3. Настройка ролей
  await execSafe("настройка ролей", async () => {
    const roles = {
      FEATURE_OWNER_ROLE: await acl.FEATURE_OWNER_ROLE(),
      GOVERNOR_ROLE: await acl.GOVERNOR_ROLE(),
      DEFAULT_ADMIN_ROLE: await acl.DEFAULT_ADMIN_ROLE(),
      FACTORY_ADMIN: IDS.FACTORY_ADMIN
    };

    // Выдаем основные роли
    for (const [roleName, roleId] of Object.entries(roles)) {
      await acl.grantRole(roleId, deployer.address);
      console.log(`Роль ${roleName} выдана: ${await acl.hasRole(roleId, deployer.address)}`);
    }
  });

  // 4. Деплой реестра
  const registry = await execSafe("деплой реестра", async () => {
    const Registry = await ethers.getContractFactory("Registry");
    const registry = await Registry.deploy();
    await registry.waitForDeployment();
    const aclAddress = await acl.getAddress();
    await registry.initialize(aclAddress);
    await registry.setCoreService(IDS.ACL_SERVICE, aclAddress);
    console.log(`Реестр: ${await registry.getAddress()}`);
    return registry;
  });

  // 5. Деплой вспомогательных контрактов
  const [gateway, priceFeed, feeManager] = await Promise.all([
    // Платежный шлюз
    execSafe("деплой платежного шлюза", async () => {
      // Проверяем, существует ли контракт MockPaymentGateway
      let Gateway;
      try {
        Gateway = await ethers.getContractFactory("MockPaymentGateway");
      } catch (error) {
        console.log('MockPaymentGateway не найден, пробуем PaymentGateway...');
        Gateway = await ethers.getContractFactory("PaymentGateway");
      }

      const gateway = await Gateway.deploy();
      await gateway.waitForDeployment();
      const gatewayAddress = await gateway.getAddress();
      console.log(`Платежный шлюз: ${gatewayAddress}`);

      // Проверяем, нужно ли инициализировать
      if (gateway.initialize && typeof gateway.initialize === 'function') {
        try {
          const aclAddress = await acl.getAddress();
          const registryAddress = await registry.getAddress();
          const feeManagerAddress = await feeManager.getAddress();

          console.log(`Инициализация платежного шлюза с параметрами:`);
          console.log(`- ACL: ${aclAddress}`);
          console.log(`- Registry: ${registryAddress}`);
          console.log(`- FeeManager: ${feeManagerAddress}`);

          await gateway.initialize(aclAddress, registryAddress, feeManagerAddress);
          console.log('Платежный шлюз успешно инициализирован');
        } catch (initError) {
          console.log('Ошибка при инициализации платежного шлюза:', initError);
          // Продолжаем даже при ошибке инициализации
        }
      }

      return gateway;
    }),

    // Ценовой фид
    execSafe("деплой ценового фида", async () => {
      const PriceFeed = await ethers.getContractFactory("MockPriceFeed");
      const priceFeed = await PriceFeed.deploy();
      await priceFeed.waitForDeployment();
      console.log(`Ценовой фид: ${await priceFeed.getAddress()}`);
      return priceFeed;
    }),

    // Менеджер комиссий
    execSafe("деплой менеджера комиссий", async () => {
      const FeeManager = await ethers.getContractFactory("CoreFeeManager");
      const feeManager = await FeeManager.deploy();
      await feeManager.waitForDeployment();
      await feeManager.initialize(await acl.getAddress());
      console.log(`Менеджер комиссий: ${await feeManager.getAddress()}`);
      return feeManager;
    })
  ]);

  // Настройка платежного шлюза
  await gateway.setFeeManager(await feeManager.getAddress());

  // 6. Деплой и настройка валидатора
  const validator = await execSafe("деплой валидатора", async () => {
    const MultiValidator = await ethers.getContractFactory("MultiValidator");
    const validator = await MultiValidator.deploy();
    await validator.waitForDeployment();
    try {
      await validator.initialize(await acl.getAddress());
    } catch (error) {
      if (error instanceof Error && error.message.includes('already initialized')) {
        console.log("Валидатор уже был инициализирован");
      } else {
        throw error;
      }
    }
    console.log(`Валидатор: ${await validator.getAddress()}`);
    return validator;
  });

  // 7. Добавление токена в валидатор
  await execSafe("добавление токена в валидатор", async () => {
    const tokenAddress = await token.getAddress();
    if (!await validator.allowed(tokenAddress)) {
      await validator.addToken(tokenAddress);
      console.log(`Токен ${tokenAddress} добавлен в валидатор: ${await validator.allowed(tokenAddress)}`);
    } else {
      console.log(`Токен ${tokenAddress} уже разрешен в валидаторе`);
    }
  });

  // 8. Деплой фабрики маркетплейса
  const marketplaceFactory = await execSafe("деплой фабрики маркетплейса", async () => {
    const MarketplaceFactory = await ethers.getContractFactory("MarketplaceFactory");
    const marketplaceFactory = await MarketplaceFactory.deploy(
      await registry.getAddress(), 
      await gateway.getAddress()
    );
    await marketplaceFactory.waitForDeployment();
    console.log(`Фабрика маркетплейса: ${await marketplaceFactory.getAddress()}`);
    return marketplaceFactory;
  });

  // 9. Регистрация модуля маркетплейса
  await execSafe("регистрация модуля маркетплейса", async () => {
    // Проверяем, зарегистрирован ли модуль
    let isRegistered = false;
    let currentAddress = ethers.ZeroAddress;

    try {
      const [moduleAddress] = await registry.getFeature(IDS.MARKETPLACE_ID);
      currentAddress = moduleAddress;
      isRegistered = moduleAddress !== ethers.ZeroAddress;
      console.log(`Статус модуля маркетплейса: ${isRegistered ? 'зарегистрирован' : 'не зарегистрирован'}`);
      if (isRegistered) {
        console.log(`Текущий адрес модуля: ${currentAddress}`);
      }
    } catch (error) {
      console.log('Ошибка при проверке регистрации модуля:', error);
    }

    // Если не зарегистрирован - регистрируем
    if (!isRegistered) {
      const factoryAddress = await marketplaceFactory.getAddress();
      console.log(`Регистрация модуля маркетплейса с адресом фабрики: ${factoryAddress}`);
      await registry.registerFeature(IDS.MARKETPLACE_ID, factoryAddress, 0);
      console.log("Модуль маркетплейса успешно зарегистрирован");
    } else {
      // Проверяем, соответствует ли текущий адрес фабрике
      const factoryAddress = await marketplaceFactory.getAddress();
      if (currentAddress.toLowerCase() !== factoryAddress.toLowerCase()) {
        console.log(`Обновление адреса модуля с ${currentAddress} на ${factoryAddress}`);
        await registry.upgradeFeature(IDS.MARKETPLACE_ID, factoryAddress);
        console.log("Адрес модуля маркетплейса обновлен");
      } else {
        console.log("Модуль маркетплейса уже зарегистрирован с правильным адресом");
      }
    }

    // Проверяем регистрацию валидатора
    const validatorAddress = await getModuleServiceByAlias(registry, IDS.MARKETPLACE_ID, IDS.VALIDATOR_ALIAS);
    if (validatorAddress === ethers.ZeroAddress) {
      console.log('Валидатор для модуля маркетплейса не зарегистрирован, регистрируем...');
      // Здесь можно добавить создание и регистрацию валидатора
    } else {
      console.log(`Валидатор для модуля маркетплейса зарегистрирован: ${validatorAddress}`);
    }
  });

  // 10. Регистрация сервисов для модуля маркетплейса
  await execSafe("регистрация сервисов", async () => {
    // Регистрация валидатора с использованием setModuleServiceAlias
    await registry.setModuleServiceAlias(
      IDS.MARKETPLACE_ID, 
      IDS.VALIDATOR_ALIAS, 
      await validator.getAddress()
    );

    // Регистрация платежного шлюза с использованием setModuleServiceAlias
    await registry.setModuleServiceAlias(
      IDS.MARKETPLACE_ID, 
      IDS.PAYMENT_GATEWAY_ALIAS, 
      await gateway.getAddress()
    );

    console.log("Сервисы зарегистрированы для модуля маркетплейса");
  });

  // 11. Создание маркетплейса напрямую
  mpAddress = await execSafe("создание маркетплейса", async () => {
    // Проверяем роль FACTORY_ADMIN и другие роли
    if (!await acl.hasRole(IDS.FACTORY_ADMIN, deployer.address)) {
      await acl.grantRole(IDS.FACTORY_ADMIN, deployer.address);
      console.log("Роль FACTORY_ADMIN выдана деплоеру");
    }

    // Проверяем, есть ли FEATURE_OWNER_ROLE
    const FEATURE_OWNER_ROLE = await acl.FEATURE_OWNER_ROLE();
    if (!await acl.hasRole(FEATURE_OWNER_ROLE, deployer.address)) {
      await acl.grantRole(FEATURE_OWNER_ROLE, deployer.address);
      console.log("Роль FEATURE_OWNER_ROLE выдана деплоеру");
    }

    // Проверяем инициализацию PaymentGateway
    if (gateway.initialize && typeof gateway.initialize === 'function') {
      try {
        await gateway.initialize(await acl.getAddress(), await registry.getAddress(), await feeManager.getAddress());
        console.log("Платежный шлюз инициализирован");
      } catch (error) {
        if (!(error instanceof Error) || !error.message.includes('already initialized')) {
          console.warn("Ошибка при инициализации платежного шлюза:", error);
        } else {
          console.log("Платежный шлюз уже инициализирован");
        }
      }
    }

    // Создаем напрямую маркетплейс вместо использования фабрики
    console.log("Создание маркетплейса напрямую...");

    // Генерируем ID для инстанса
    const instanceId = ethers.keccak256(ethers.toUtf8Bytes(`Marketplace:Instance:${Date.now()}`));
    console.log(`Создан ID инстанса: ${instanceId}`);

    // Регистрируем модуль и сервисы
    await registry.registerFeature(instanceId, deployer.address, 1);
    console.log("Зарегистрирован новый модуль");

    // Регистрируем сервисы для нового модуля
    const validatorAddress = await validator.getAddress();
    // Используем setModuleServiceAlias чтобы избежать неоднозначности
    await registry.setModuleServiceAlias(instanceId, "Validator", validatorAddress);
    console.log(`Зарегистрирован валидатор (${validatorAddress}) для нового модуля`);

    const gatewayAddress = await gateway.getAddress();
    // Используем setModuleServiceAlias для PaymentGateway
    await registry.setModuleServiceAlias(instanceId, "PaymentGateway", gatewayAddress);
    console.log(`Зарегистрирован платежный шлюз (${gatewayAddress}) для нового модуля`);

      // Проверяем, что платежный шлюз корректно зарегистрирован для этого модуля
    // Поскольку функция getModuleServiceByAlias ещё не обновилась в ABI, вызываем функцию через низкоуровневый интерфейс
    const registeredGateway = await registry.getFunction('getModuleService(bytes32,bytes32)').staticCall(instanceId, CONSTANTS.PAYMENT_GATEWAY_SERVICE);
    if (registeredGateway !== gatewayAddress) {
      console.log(`Несоответствие в адресе платежного шлюза: ожидается ${gatewayAddress}, получено ${registeredGateway}`);
      console.log("Повторная регистрация платежного шлюза...");
      await registry.setModuleServiceAlias(instanceId, IDS.PAYMENT_GATEWAY_ALIAS, gatewayAddress);
    }

    // Создаем маркетплейс
    const Marketplace = await ethers.getContractFactory("Marketplace");
    const marketplace = await Marketplace.deploy(
      await registry.getAddress(), 
      gatewayAddress, 
      instanceId
    );

    await marketplace.waitForDeployment();
    console.log("Маркетплейс развернут");

    // Обновляем реестр
    const newMarketplaceAddress = await marketplace.getAddress();
    await registry.upgradeFeature(instanceId, newMarketplaceAddress);
    console.log(`Маркетплейс обновлен в реестре: ${newMarketplaceAddress}`);

    // Обновляем глобальную переменную
    marketplaceAddress = newMarketplaceAddress;

    return newMarketplaceAddress;
  });

  // Выводим информацию о созданном маркетплейсе
  console.log(`Полученный маркетплейс: ${marketplaceAddress || mpAddress}`);

  // Проверяем, что все необходимые значения определены
  if (!token || !priceFeed || !registry || !gateway || !acl || !validator || !marketplaceFactory) {
    throw new Error("Не все контракты были успешно инициализированы");
  }

  // Возвращаем объект с результатами
  return { 
    marketplaceFactory, 
    token, 
    priceFeed, 
    registry, 
    gateway, 
    acl, 
    marketplaceAddress: mpAddress ?? marketplaceAddress ?? "", 
    validator 
  };
}

  /**
   * Основная функция демонстрации маркетплейса
   */
  async function main(): Promise<any> {
  try {
    const [deployer, seller, buyer] = await ethers.getSigners();

    // 1. Деплой базовых контрактов
    console.log("Деплой базовых контрактов...");
    const { marketplaceFactory, token, priceFeed, registry, gateway, acl, marketplaceAddress: coreMarketplaceAddress, validator } = await setupDemoEnvironment();
    let marketplaceAddress = coreMarketplaceAddress;

    if (marketplaceAddress && marketplaceAddress !== "") {
      console.log(`Используем существующий маркетплейс: ${marketplaceAddress}`);
    }

    // 2. Настройка прав доступа для продавца
    await execSafe("настройка прав продавца", async () => {
      if (acl) {
        const GOVERNOR_ROLE = await acl.GOVERNOR_ROLE();
        await acl.grantRole(GOVERNOR_ROLE, seller.address);
        await acl.grantRole(IDS.FACTORY_ADMIN, seller.address);
        console.log(`Роли выданы продавцу: ${seller.address}`);
      }
    });

    // 3. Создаем маркетплейс через фабрику, если он еще не создан
    if (!marketplaceAddress || marketplaceAddress === "") {
      await execSafe("создание маркетплейса", async () => {
        if (!marketplaceFactory) throw new Error("marketplaceFactory не инициализирован");

        // Пробуем создать через фабрику
        try {
          const tx = await marketplaceFactory.createMarketplace();
          const receipt = await tx.wait();

          // Извлекаем адрес из событий
          const marketplaceCreatedEvent = receipt.logs.find((log: any) => 
            log.topics?.[0] === ethers.id("MarketplaceCreated(address,address)"));

          if (marketplaceCreatedEvent) {
            const iface = new ethers.Interface(["event MarketplaceCreated(address indexed creator, address marketplace)"]);
            const decoded = iface.parseLog({
              topics: marketplaceCreatedEvent.topics as string[],
              data: marketplaceCreatedEvent.data as string
            });

            if (decoded && decoded.args) {
              marketplaceAddress = decoded.args.marketplace.toString();
              console.log(`Маркетплейс создан: ${marketplaceAddress}`);
            }
          }
        } catch (error) {
          console.log("Ошибка при создании через фабрику, создаем напрямую...");

          // Создаем напрямую
          const instanceId = ethers.keccak256(ethers.toUtf8Bytes(`MarketInstance:${Date.now()}`));

          // Регистрируем и настраиваем
          await registry.registerFeature(instanceId, deployer.address, 1);

          // Получаем и устанавливаем валидатор
          const validatorAddr = await getModuleServiceByAlias(registry, CONSTANTS.MARKETPLACE_ID, CONSTANTS.VALIDATOR_ALIAS);
          console.log(`Найден валидатор модуля маркетплейса: ${validatorAddr}`);

          // Если валидатор не найден, нужно создать новый
          if (validatorAddr === ethers.ZeroAddress) {
            console.log('Создаем и инициализируем новый валидатор');
            const MultiValidator = await ethers.getContractFactory('MultiValidator');
            const newValidator = await MultiValidator.deploy();
            await newValidator.waitForDeployment();
            const newValidatorAddr = await newValidator.getAddress();
            console.log(`Новый валидатор развернут: ${newValidatorAddr}`);

            try {
              await newValidator.initialize(await acl.getAddress());
              console.log('Новый валидатор инициализирован');
            } catch (error) {
              console.log('Ошибка при инициализации валидатора:', error);
              // Продолжаем даже при ошибке инициализации
            }

            // Регистрируем новый валидатор
            await registry.setModuleServiceAlias(instanceId, CONSTANTS.VALIDATOR_ALIAS, newValidatorAddr);
            console.log(`Установлен новый валидатор: ${newValidatorAddr}`);
          } else {
            // Используем существующий валидатор
            await registry.setModuleServiceAlias(instanceId, CONSTANTS.VALIDATOR_ALIAS, validatorAddr);
            console.log(`Установлен валидатор: ${validatorAddr}`);
          }

          // Получаем и устанавливаем платежный шлюз
          const gatewayAddr = await gateway.getAddress();
          // Используем setModuleServiceAlias для установки платежного шлюза
          await registry.setModuleServiceAlias(instanceId, CONSTANTS.PAYMENT_GATEWAY_ALIAS, gatewayAddr);
          console.log(`Установлен платежный шлюз напрямую: ${gatewayAddr}`);

          // Проверяем, что платежный шлюз был правильно зарегистрирован
          const registeredGateway = await getModuleServiceByAlias(registry, instanceId, CONSTANTS.PAYMENT_GATEWAY_ALIAS);
          console.log(`Зарегистрированный платежный шлюз для инстанса: ${registeredGateway}`);

          // Получаем адреса всех необходимых контрактов
          const registryAddress = await registry.getAddress();
          const gatewayAddress = await gateway.getAddress();

          console.log(`Параметры для создания маркетплейса:`);
          console.log(`- Реестр: ${registryAddress}`);
          console.log(`- Платежный шлюз: ${gatewayAddress}`);
          console.log(`- ID инстанса: ${instanceId}`);

          try {
            // Получаем фабрику контракта Marketplace
            let marketplaceFactory;
            try {
              marketplaceFactory = await ethers.getContractFactory("Marketplace");
              console.log('Контракт маркетплейса найден и подготовлен, начинаем деплой...');
            } catch (contractError) {
              console.error('Ошибка при поиске контракта Marketplace:', contractError);
              throw new Error('Контракт Marketplace не найден в проекте');
            }

            // Используем полученную фабрику для деплоя
            const marketplace = await marketplaceFactory.deploy(
              registryAddress,
              gatewayAddress,
              instanceId
            );

            console.log(`Транзакция деплоя отправлена: ${marketplace.deploymentTransaction()?.hash}`);
            await marketplace.waitForDeployment();
            console.log('Маркетплейс успешно развернут');
          } catch (error) {
            console.error('Ошибка при создании маркетплейса:', error);
            throw error;
          }

          // Обновляем
          const createdAddress = await marketplace.getAddress();
          await registry.upgradeFeature(instanceId, createdAddress);
          marketplaceAddress = createdAddress;
          console.log(`Маркетплейс создан напрямую: ${marketplaceAddress}`);
        }
      });
    }

    // 4. Настройка токенов и цен
    await execSafe("настройка токенов", async () => {
      if (!token) throw new Error("token не инициализирован");

      const tokenAddress = await token.getAddress();
      const gatewayAddress = await gateway.getAddress();

      // Разрешаем платежному шлюзу тратить токены
      const erc20Interface = new ethers.Interface(["function approve(address spender, uint256 amount) external returns (bool)"]);
      const approveData = erc20Interface.encodeFunctionData("approve", [gatewayAddress, ethers.parseEther("1000")]);
      await deployer.sendTransaction({ to: tokenAddress, data: approveData });

      // Устанавливаем цену в фиде
      if (priceFeed) {
        await priceFeed.setPrice(tokenAddress, ethers.parseEther("1"));
      }

      console.log(`Токен настроен: ${tokenAddress}`);
    });

    // 5. Создание товара на маркетплейсе
    if (!marketplaceAddress) {
      throw new Error("Не удалось получить адрес маркетплейса");
    }

    console.log(`Используем маркетплейс: ${marketplaceAddress}`);

    // Метаданные листинга
    const metadata = ethers.toUtf8Bytes(JSON.stringify({
      title: "Premium Ebook Bundle",
      description: "Коллекция из 5 электронных книг по программированию",
      imageUrl: "https://example.com/image.jpg",
      features: ["PDF и EPUB форматы", "Доступ навсегда", "Обновления включены"]
    }));

    // Создаем товар
    const marketplace = await ethers.getContractAt("Marketplace", marketplaceAddress, seller);
    const tokenAddress = await token.getAddress();

    // Определяем формат метода list
    let hasMetadataParam = false;
    try {
      const listFunction = marketplace.interface.getFunction('list');
      hasMetadataParam = listFunction !== null && listFunction.inputs.length > 2;
    } catch {}

    // Создаем листинг
    const { listingReceipt } = await execSafe("создание листинга", async () => {
      const tx = hasMetadataParam
        ? await marketplace.list(tokenAddress, ethers.parseEther("25"), metadata)
        : await marketplace.list(tokenAddress, ethers.parseEther("25"));

      console.log(`Транзакция отправлена: ${tx.hash}`);
      const receipt = await tx.wait();
      return { listingReceipt: receipt };
    });

    // 6. Получение информации о созданном товаре
    let listingId = await execSafe("получение ID листинга", async () => {
      const eventSignature = "MarketplaceListingCreated(uint256,address,address,uint256)";
      const eventLog = listingReceipt?.logs?.find((log: any) => 
        log.topics?.[0] === ethers.id(eventSignature));

      if (eventLog) {
        const decodedLog = marketplace.interface.decodeEventLog(
          eventSignature,
          eventLog.data,
          eventLog.topics
        );
        return decodedLog[0]; // ID листинга
      }
      throw new Error("Не удалось получить ID листинга");
    });

    console.log(`Товар создан с ID: ${listingId}`);

    // Получаем данные о товаре
    const listing = await marketplace.listings(listingId);
    console.log("Детали товара:");
    console.log(`  ID: ${listingId}`);
    console.log(`  Продавец: ${listing[0]}`);
    console.log(`  Токен: ${listing[1]}`);
    console.log(`  Цена: ${ethers.formatEther(listing[2])} USDC`);
    console.log(`  Активен: ${listing[3]}`);

    // 7. Подготовка к покупке
    await execSafe("подготовка к покупке", async () => {
      if (!buyer) throw new Error("buyer не инициализирован");

      // Перевод токенов покупателю
      const transferInterface = new ethers.Interface(["function transfer(address to, uint256 amount) external returns (bool)"]);
      const transferData = transferInterface.encodeFunctionData("transfer", [buyer.address, ethers.parseEther("100")]);
      await deployer.sendTransaction({
        to: tokenAddress,
        data: transferData
      });

      // Разрешение на списание
      const buyerApproveInterface = new ethers.Interface(["function approve(address spender, uint256 amount) external returns (bool)"]);
      const buyerApproveData = buyerApproveInterface.encodeFunctionData("approve", [await gateway.getAddress(), ethers.parseEther("100")]);
      await buyer.sendTransaction({
        to: tokenAddress,
        data: buyerApproveData
      });

      console.log("Покупатель готов к покупке");
    });

    // 8. Покупка товара
    const { purchaseRc } = await execSafe("покупка товара", async () => {
      if (!buyer) throw new Error("buyer не инициализирован");

      // Подключаемся к маркетплейсу от имени покупателя
      const marketplaceForBuyer = await ethers.getContractAt("Marketplace", marketplaceAddress, buyer);

      // Покупаем товар
      const tx = await marketplaceForBuyer.buy(listingId);
      console.log(`Транзакция покупки отправлена: ${tx.hash}`);
      const receipt = await tx.wait();
      console.log("Транзакция покупки подтверждена");

      return { purchaseRc: receipt };
    });

    // 9. Проверка результата покупки
    await execSafe("проверка покупки", async () => {
      // Проверяем статус товара
      const marketplaceAfterBuy = await ethers.getContractAt("Marketplace", marketplaceAddress);
      const listingAfter = await marketplaceAfterBuy.listings(listingId);
      console.log(`Товар активен после покупки: ${listingAfter[3]}`);

      // Ищем событие покупки
      let buyerFromEvent = null;

      // Метод 1: через фрагмент
      const soldEvent = purchaseRc?.logs?.find((log: any) => 
        'fragment' in log && log.fragment?.name === "MarketplaceListingSold" && 'args' in log);

      if (soldEvent && 'args' in soldEvent) {
        buyerFromEvent = (soldEvent.args as any).buyer;
        console.log(`Покупатель из события: ${buyerFromEvent}`);
        console.log(`ID товара из события: ${(soldEvent.args as any).id?.toString()}`);
      }

      // Метод 2: через темы (если первый не сработал)
      if (!buyerFromEvent) {
        const topicLog = purchaseRc?.logs?.find((log: any) => 
          log.topics?.[0] === ethers.id("MarketplaceListingSold(uint256,address)"));

        if (topicLog) {
          const iface = new ethers.Interface(["event MarketplaceListingSold(uint256 indexed id, address indexed buyer)"]);
          const decoded = iface.parseLog({
            topics: Array.isArray(topicLog.topics) ? topicLog.topics : [],
            data: typeof topicLog.data === 'string' ? topicLog.data : '0x'
          });

          if (decoded && decoded.args) {
            buyerFromEvent = decoded.args.buyer as string;
            console.log(`Покупатель из события: ${buyerFromEvent}`);
            console.log(`ID товара из события: ${decoded.args.id?.toString() || 'неизвестно'}`);
          }
        }
      }
    });

    // 10. Проверка балансов и финализация
    const { sellerBalance, buyerBalance } = await execSafe("проверка балансов", async () => {
      if (!seller || !buyer) throw new Error("seller или buyer не инициализированы");

      // Проверяем балансы
      const sellerBalance = await token.balanceOf(seller.address);
      const buyerBalance = await token.balanceOf(buyer.address);

      console.log(`Баланс продавца: ${ethers.formatEther(sellerBalance)} USDC`);
      console.log(`Баланс покупателя: ${ethers.formatEther(buyerBalance)} USDC`);

      // Финальная проверка товара
      const marketplaceAfterBuy = await ethers.getContractAt("Marketplace", marketplaceAddress);
      const finalListing = await marketplaceAfterBuy.listings(listingId);
      console.log(`Финальный статус товара: активен = ${finalListing[3]}`);

      return { sellerBalance, buyerBalance };
    });

    console.log("Демонстрация маркетплейса успешно завершена!");

    // Формируем результат
    const result: any = { marketplace: marketplaceAddress };

    try {
      if (token) result.token = await token.getAddress();
      if (listingId !== undefined) result.listingId = listingId;
      if (sellerBalance) result.sellerBalance = sellerBalance;
      if (buyerBalance) result.buyerBalance = buyerBalance;
    } catch (e) {
      console.error("Ошибка при формировании результата:", e);
    }

    console.log("Результат выполнения скрипта:", result);
    return result;

  } catch (error) {
    const typedError = error as Error;
    console.error("Ошибка в main:", typedError);
    throw typedError;
  }
}


// Запускаем демонстрацию, если скрипт выполняется напрямую
if (require.main === module) {
  main()
    .then(() => console.log("Демонстрация успешно завершена"))
    .catch((error: Error) => {
      console.error("Ошибка при выполнении демонстрации:", error);
      process.exitCode = 1;
    });
}

