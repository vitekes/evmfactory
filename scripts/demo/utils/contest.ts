import { ethers } from "hardhat";
import { PrizeType } from "./constants";
import { getAddressFromEvents } from "./helpers";

export interface PrizeInfo {
  prizeType: PrizeType;
  token: string;
  amount: bigint;
  distribution: number;
  uri: string;
}

/**
 * Deploys a contest via ContestFactory and returns the escrow address
 */
export async function createContest(
  factory: any,
  token: string,
  metadata: string = "0x"
): Promise<string> {
  // Проверяем и выдаем роль GOVERNOR_ROLE перед созданием конкурса
  const [deployer] = await ethers.getSigners();
  console.log(`Проверка наличия роли GOVERNOR_ROLE для ${deployer.address}...`);

  // Получаем адрес реестра из фабрики
  const registryAddress = await factory.registry();
  const registry = await ethers.getContractAt("Registry", registryAddress);

  // Получаем адрес AccessControlCenter из реестра
  const aclAddress = await registry.getCoreService(ethers.keccak256(ethers.toUtf8Bytes("AccessControlCenter")));
  const acl = await ethers.getContractAt("AccessControlCenter", aclAddress);

  // Получаем идентификатор роли GOVERNOR_ROLE
  const governorRole = await acl.GOVERNOR_ROLE();

  // Проверяем, есть ли у деплойера роль GOVERNOR_ROLE
  const hasRole = await acl.hasRole(governorRole, deployer.address);
  console.log(`У адреса ${deployer.address} ${hasRole ? 'уже есть' : 'нет'} роли GOVERNOR_ROLE`);

  // Если роли нет, выдаем её
  if (!hasRole) {
    console.log(`Выдаем роль GOVERNOR_ROLE для ${deployer.address}...`);
    const tx = await acl.grantRole(governorRole, deployer.address);
    await tx.wait();
    console.log(`Роль GOVERNOR_ROLE успешно выдана для ${deployer.address}`);
  }

  // Проверяем настройку валидатора в реестре перед созданием конкурса
  console.log("Проверка настройки валидатора...");
  try {
    const contestModuleId = ethers.keccak256(ethers.toUtf8Bytes("Contest"));
    const validator = await registry.getModuleServiceByAlias(contestModuleId, "Validator");
    console.log(`Адрес валидатора из реестра: ${validator}`);

    // Если валидатор не зарегистрирован или равен нулевому адресу, регистрируем его
    if (validator === ethers.ZeroAddress) {
      console.log("Валидатор не зарегистрирован или имеет нулевой адрес. Регистрируем...");

      // Пытаемся получить адрес валидатора из реестра через другой метод
      const validatorAddr = await registry.getModuleService(contestModuleId, ethers.keccak256(ethers.toUtf8Bytes("Validator")));
      console.log(`Адрес валидатора через getModuleService: ${validatorAddr}`);

      if (validatorAddr === ethers.ZeroAddress) {
        // Получаем валидатор через импорт из основного скрипта
        const validatorFactory = await ethers.getContractFactory("MultiValidator");
        const deployedValidator = await validatorFactory.deploy();
        await deployedValidator.waitForDeployment();
        await deployedValidator.initialize(aclAddress);
        const newValidatorAddr = await deployedValidator.getAddress();
        console.log(`Создан новый валидатор: ${newValidatorAddr}`);

        // Добавляем токен в валидатор
        await deployedValidator.addToken(token);
        console.log(`Токен ${token} добавлен в валидатор`);

        // Регистрируем валидатор в реестре
        await registry.setModuleServiceAlias(contestModuleId, "Validator", newValidatorAddr);
        console.log(`Валидатор зарегистрирован в реестре: ${newValidatorAddr}`);
      } else {
        // Регистрируем существующий валидатор в реестре через алиас
        await registry.setModuleServiceAlias(contestModuleId, "Validator", validatorAddr);
        console.log(`Существующий валидатор зарегистрирован через алиас: ${validatorAddr}`);
      }
    }

    // Проверяем, что токен разрешен в валидаторе
    const validatorContract = await ethers.getContractAt("MultiValidator", validator);
    let isTokenAllowed = false;
    try {
      if ('allowed' in validatorContract && typeof validatorContract.allowed === 'function') {
        isTokenAllowed = await validatorContract.allowed(token);
      } else if ('isAllowed' in validatorContract && typeof validatorContract.isAllowed === 'function') {
        isTokenAllowed = await validatorContract.isAllowed(token);
      }

      console.log(`Токен ${token} ${isTokenAllowed ? 'разрешен' : 'не разрешен'} в валидаторе`);

      if (!isTokenAllowed) {
        console.log(`Добавляем токен ${token} в валидатор...`);
        await validatorContract.addToken(token);
        console.log(`Токен успешно добавлен в валидатор`);
      }
    } catch (error) {
      console.log(`Ошибка при проверке токена в валидаторе: ${error instanceof Error ? error.message : 'Неизвестная ошибка'}`);
    }
  } catch (error) {
    console.log(`Ошибка при проверке валидатора: ${error instanceof Error ? error.message : 'Неизвестная ошибка'}`);
  }

  // Создаем упрощенный список призов для отладки
  const prizes: PrizeInfo[] = [
    {
      prizeType: PrizeType.MONETARY,
      token,
      amount: ethers.parseEther("10"),
      distribution: 0,
      uri: ""
    }
  ];

  console.log("Вызываем createContest с параметрами:");
  console.log("- Токен:", token);
  console.log("- Сумма приза:", ethers.formatEther(prizes[0].amount));
  console.log("- Тип приза:", prizes[0].prizeType);

  // Проверяем и увеличиваем одобрение токенов перед созданием конкурса
  try {
    const tokenContract = await ethers.getContractAt("TestToken", token);
    const factoryAddress = await factory.getAddress();

    // Получаем текущее одобрение
    const currentAllowance = await tokenContract.allowance(deployer.address, factoryAddress);
    console.log(`Текущее одобрение для фабрики: ${ethers.formatEther(currentAllowance)}`);

    // Проверяем, достаточно ли одобрения
    const requiredAmount = prizes[0].amount;
    if (currentAllowance < requiredAmount) {
      console.log(`Увеличиваем одобрение для фабрики конкурсов с ${ethers.formatEther(currentAllowance)} до ${ethers.formatEther(requiredAmount)}...`);
      const approveTx = await tokenContract.approve(factoryAddress, requiredAmount);
      await approveTx.wait();
      console.log(`Одобрение для фабрики конкурсов увеличено до ${ethers.formatEther(requiredAmount)}`);
    } else {
      console.log(`Текущее одобрение ${ethers.formatEther(currentAllowance)} достаточно для создания конкурса`);
    }
  } catch (error) {
    console.log(`Ошибка при проверке/увеличении одобрения: ${error instanceof Error ? error.message : 'Неизвестная ошибка'}`);
  }

  // Добавляем информацию о балансе
  try {
    const tokenContract = await ethers.getContractAt("TestToken", token);
    const balance = await tokenContract.balanceOf(deployer.address);
    console.log(`Баланс токенов у создателя: ${ethers.formatEther(balance)}`);

    // Проверяем, достаточно ли токенов
    if (balance < prizes[0].amount) {
      console.log(`Недостаточно токенов для создания конкурса. Пробуем минтить...`);
      // Пробуем минтить, если есть такая функция
      if ('mint' in tokenContract && typeof tokenContract.mint === 'function') {
        await tokenContract.mint(deployer.address, ethers.parseEther("100"));
        const newBalance = await tokenContract.balanceOf(deployer.address);
        console.log(`Токены заминчены. Новый баланс: ${ethers.formatEther(newBalance)}`);
      } else {
        console.log(`Функция mint недоступна для данного токена`);
      }
    }
  } catch (error) {
    console.log(`Ошибка при проверке баланса: ${error instanceof Error ? error.message : 'Неизвестная ошибка'}`);
  }

  // Теперь выполняем вызов с трассировкой стека
  console.log(`Создаем конкурс...`);
  let tx;
  try {
    tx = await factory.createContest(prizes, metadata);
  } catch (error) {
    // Подробно логируем ошибку
    console.error(`Детальная ошибка при создании конкурса:`, error);

    // Пробуем получить детали ошибки через вызов метода с gasLimit
    try {
      console.log(`Пробуем вызвать createContest с увеличенным gasLimit...`);
      const result = await factory.createContest.staticCall(prizes, metadata, { gasLimit: 5000000 });
      console.log(`Статический вызов вернул результат:`, result);
    } catch (staticError) {
      console.log(`Статический вызов тоже провалился:`, staticError);
    }

    throw error;
  }
  const receipt = await tx.wait();
  const contestAddr = getAddressFromEvents(
    receipt,
    "ContestCreated",
    "ContestCreated(address,address,uint256)",
    1
  );
  if (!contestAddr) {
    throw new Error("contest address not found");
  }
  return contestAddr;
}

/**
 * Finalizes a contest and distributes prizes
 */
export async function finalizeContest(
  contestAddress: string,
  winners: string[]
): Promise<void> {
  const escrow = await ethers.getContractAt("ContestEscrow", contestAddress);
  const tx = await escrow.finalize(winners, 0n);
  await tx.wait();
}
