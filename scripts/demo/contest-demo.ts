import { ethers } from "hardhat";
import { deployCore, registerModule } from "./utils/deployer";
import { safeExecute, getAddressFromEvents } from "./utils/helpers";
import { CONSTANTS, PrizeType } from "./utils/constants";

/**
 * Создает конкурс с использованием ContestFactory
 * @param factory Контракт фабрики конкурсов
 * @param token Адрес токена для призов
 * @param metadata Метаданные конкурса
 */
async function createContest(factory: any, token: string, metadata: string = "0x") {
  const prizes = [
    { 
      prizeType: PrizeType.MONETARY, 
      token, 
      amount: ethers.parseEther("10"), 
      distribution: 0, 
      uri: "" 
    },
    { 
      prizeType: PrizeType.MONETARY, 
      token, 
      amount: ethers.parseEther("5"), 
      distribution: 0, 
      uri: "" 
    },
    { 
      prizeType: PrizeType.PROMO, 
      token: ethers.ZeroAddress, 
      amount: 0, 
      distribution: 0, 
      uri: "ipfs://promo_reward" 
    }
  ];

  console.log("Создание конкурса...");
  const tx = await factory.createContest(prizes, metadata);
  console.log("Транзакция отправлена:", tx.hash);
  const receipt = await tx.wait();
  console.log("Транзакция подтверждена");

  const contestAddr = getAddressFromEvents(
    receipt, 
    "ContestCreated", 
    "ContestCreated(address,address,uint256)", 
    1
  );

  if (!contestAddr) {
    throw new Error("Не удалось получить адрес созданного конкурса");
  }

  console.log("Получен адрес конкурса:", contestAddr);
  return contestAddr;
}

/**
 * Главная функция демонстрации конкурсов
 */
async function main() {
  // Получаем аккаунты для тестирования
  const [deployer, participant1, participant2, participant3] = await ethers.getSigners();
  console.log("Демонстрация функциональности конкурсов");
  console.log("=======================================\n");
  console.log(`Деплоер: ${deployer.address}`);
  console.log(`Участник 1: ${participant1.address}`);
  console.log(`Участник 2: ${participant2.address}`);
  console.log(`Участник 3: ${participant3.address}\n`);

  // 1. Деплой базовых контрактов
  console.log("1. Разворачиваем базовые контракты системы");
  console.log("----------------------------------------\n");
  const { token, registry, gateway, validator, acl } = await deployCore();

  // 2. Деплой фабрики конкурсов
  console.log("\n2. Разворачиваем фабрику конкурсов");
  console.log("----------------------------------\n");
  const contestFactory = await safeExecute("деплой фабрики конкурсов", async () => {
    const Factory = await ethers.getContractFactory("ContestFactory");
    const factory = await Factory.deploy(
      await registry.getAddress(),
      await gateway.getAddress()
    );
    await factory.waitForDeployment();
    console.log(`Фабрика конкурсов развернута: ${await factory.getAddress()}`);
    return factory;
  });

  // 3. Регистрация модуля конкурсов
  console.log("\n3. Регистрируем модуль конкурсов в реестре");
  console.log("----------------------------------------\n");
  await registerModule(
    registry,
    CONSTANTS.CONTEST_ID,
    await contestFactory.getAddress(),
    await validator.getAddress(),
    await gateway.getAddress()
  );

  // 4. Создание конкурса
  console.log("\n4. Создаем новый конкурс");
  console.log("------------------------\n");

  // Сначала нужно одобрить токены для использования фабрикой
  await safeExecute("одобрение токенов для фабрики", async () => {
    await token.approve(await contestFactory.getAddress(), ethers.parseEther("1000"));
    console.log(`Токены одобрены для использования фабрикой`);
  });

  // Создаем конкурс
  const contestAddress = await safeExecute("создание конкурса", async () => {
    return createContest(contestFactory, await token.getAddress());
  });

  // 5. Завершение конкурса
  console.log("\n5. Завершаем конкурс и распределяем призы");
  console.log("----------------------------------------\n");
  await safeExecute("финализация конкурса", async () => {
    const escrow = await ethers.getContractAt("ContestEscrow", contestAddress);

    // Определяем победителей
    const winners = [
      participant1.address,  // Первое место - получит 10 ETH
      participant2.address,  // Второе место - получит 5 ETH
      participant3.address   // Третье место - получит промо-приз
    ];

    console.log("Устанавливаем победителей конкурса:");
    console.log(`1 место: ${winners[0]}`);
    console.log(`2 место: ${winners[1]}`);
    console.log(`3 место: ${winners[2]}`);

    // Финализируем конкурс с указанием победителей
    const finalizeTx = await escrow.finalize(winners, 0n, 0n);
    console.log("Транзакция финализации отправлена:", finalizeTx.hash);
    const receipt = await finalizeTx.wait();
    console.log("Конкурс успешно финализирован");

    // Выводим события финализации
    console.log("\nСобытия финализации:");
    if (receipt && receipt.logs) {
      for (const log of receipt.logs) {
        if (log.fragment) {
          console.log(`  ${log.fragment.name} ->`, log.args);
        }
      }
    } else {
      console.log("Логи недоступны в receipt");
    }
  });

  // 6. Проверка балансов победителей
  console.log("\n6. Проверяем балансы победителей");
  console.log("-------------------------------\n");
  const bal1 = await token.balanceOf(participant1.address);
  const bal2 = await token.balanceOf(participant2.address);
  const bal3 = await token.balanceOf(participant3.address);

  console.log(`Баланс победителя 1 (${participant1.address}): ${ethers.formatEther(bal1)} USDC`);
  console.log(`Баланс победителя 2 (${participant2.address}): ${ethers.formatEther(bal2)} USDC`);
  console.log(`Баланс победителя 3 (${participant3.address}): ${ethers.formatEther(bal3)} USDC`);

  console.log("\nДемонстрация успешно завершена!");
}

// Запускаем скрипт
main().catch((error) => {
  console.error("Ошибка при выполнении демонстрации:", error);
  process.exit(1);
});
