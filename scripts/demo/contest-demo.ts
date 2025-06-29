import { ethers } from "hardhat";
import { deployCore, registerModule } from "./utils/deployer";
import { CONSTANTS } from "./utils/constants";
import { safeExecute } from "./utils/helpers";
import { createContest, finalizeContest } from "./utils/contest";

async function main() {
  const [deployer, p1, p2, p3] = await ethers.getSigners();

  console.log("=== Contest Demo ===\n");
  console.log(`Deployer: ${deployer.address}`);
  console.log(`Participant1: ${p1.address}`);
  console.log(`Participant2: ${p2.address}`);
  console.log(`Participant3: ${p3.address}\n`);

  const { token, registry, gateway, validator, feeManager, acl } = await deployCore();

  const contestFactory = await safeExecute("deploy contest factory", async () => {
    const Factory = await ethers.getContractFactory("ContestFactory");
    const factory = await Factory.deploy(
      await registry.getAddress(),
      await feeManager.getAddress()
    );
    await factory.waitForDeployment();
    console.log(`Фабрика конкурсов развернута по адресу: ${await factory.getAddress()}`);
    return factory;
  });

  // Явно указываем все службы в правильном порядке
  await safeExecute("регистрация модуля конкурсов", async () => {
    // Получаем адреса всех контрактов
    const registryAddress = await registry.getAddress();
    const factoryAddress = await contestFactory.getAddress();
    const validatorAddress = await validator.getAddress();
    const gatewayAddress = await gateway.getAddress();

    console.log(`Регистрация фабрики конкурсов в реестре...`);
    console.log(`- ID модуля: ${CONSTANTS.CONTEST_ID}`);
    console.log(`- Адрес фабрики: ${factoryAddress}`);

    // Регистрируем фичу
    await registry.registerFeature(CONSTANTS.CONTEST_ID, factoryAddress, 0);
    console.log(`Фабрика конкурсов зарегистрирована в реестре`);

    // Устанавливаем валидатор напрямую по строковому алиасу
    console.log(`Регистрация валидатора для модуля конкурсов...`);
    console.log(`- Адрес валидатора: ${validatorAddress}`);
    await registry.setModuleServiceAlias(CONSTANTS.CONTEST_ID, "Validator", validatorAddress);
    console.log(`Валидатор зарегистрирован для модуля конкурсов`);

    // Устанавливаем платежный шлюз
    console.log(`Регистрация платежного шлюза для модуля конкурсов...`);
    console.log(`- Адрес платежного шлюза: ${gatewayAddress}`);
    await registry.setModuleServiceAlias(CONSTANTS.CONTEST_ID, "PaymentGateway", gatewayAddress);
    console.log(`Платежный шлюз зарегистрирован для модуля конкурсов`);

    // Добавляем токен в валидатор, если он еще не добавлен
    const tokenAddress = await token.getAddress();
    console.log(`Проверка токена ${tokenAddress} в валидаторе...`);

    let isTokenAllowed = false;
    try {
      if ('allowed' in validator && typeof validator.allowed === 'function') {
        isTokenAllowed = await validator.allowed(tokenAddress);
      } else if ('isAllowed' in validator && typeof validator.isAllowed === 'function') {
        isTokenAllowed = await validator.isAllowed(tokenAddress);
      }

      if (!isTokenAllowed) {
        console.log(`Добавление токена ${tokenAddress} в валидатор...`);
        await validator.addToken(tokenAddress);
        console.log(`Токен успешно добавлен в валидатор`);
      } else {
        console.log(`Токен уже разрешен в валидаторе`);
      }
    } catch (error) {
      console.log(`Ошибка при проверке/добавлении токена: ${error instanceof Error ? error.message : 'Неизвестная ошибка'}`);
    }
  });

  await safeExecute("prepare tokens for contest", async () => {
    // Проверяем баланс токенов у создателя
    const deployerBalance = await token.balanceOf(deployer.address);
    console.log(`Текущий баланс токенов у создателя: ${ethers.formatEther(deployerBalance)}`);

    // Если баланса недостаточно, пробуем минтить токены
    if (deployerBalance < ethers.parseEther("20")) {
      console.log(`Недостаточно токенов, минтим дополнительные...`);
      if ('mint' in token && typeof token.mint === 'function') {
        await token.mint(deployer.address, ethers.parseEther("100"));
        const newBalance = await token.balanceOf(deployer.address);
        console.log(`Новый баланс после минтинга: ${ethers.formatEther(newBalance)}`);
      } else {
        console.log(`ПРЕДУПРЕЖДЕНИЕ: Функция mint недоступна в контракте токена`);
      }
    }

    // Одобряем токены для фабрики конкурсов
    const factoryAddress = await contestFactory.getAddress();
    console.log(`Одобряем токены для фабрики конкурсов (${factoryAddress})...`);
    await token.approve(factoryAddress, ethers.parseEther("1000"));

    // Проверяем, что одобрение успешно установлено
    const allowance = await token.allowance(deployer.address, factoryAddress);
    console.log(`Установленное одобрение: ${ethers.formatEther(allowance)}`);
  });

  const contestAddress = await safeExecute("create contest", async () => {
    return createContest(contestFactory, await token.getAddress());
  });

  await safeExecute("finalize contest", async () => {
    const winners = [p1.address, p2.address, p3.address];
    await finalizeContest(contestAddress, winners);
  });

  const [bal1, bal2, bal3] = await Promise.all([
    token.balanceOf(p1.address),
    token.balanceOf(p2.address),
    token.balanceOf(p3.address)
  ]);
  console.log(`Winner1 balance: ${ethers.formatEther(bal1)} tokens`);
  console.log(`Winner2 balance: ${ethers.formatEther(bal2)} tokens`);
  console.log(`Winner3 balance: ${ethers.formatEther(bal3)} tokens`);

  console.log("\n✅ Demo finished");
}

main().catch((error) => {
  console.error("Demo failed", error);
  process.exitCode = 1;
});
