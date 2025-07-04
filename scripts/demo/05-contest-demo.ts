import { ethers } from 'hardhat';
import { keccak256, toUtf8Bytes } from 'ethers';
import { executeTransaction } from './utils/contracts';

async function main() {
  console.log('=== Демонстрация: Работа с модулем конкурсов ===');

  // Получаем аккаунты
  const [admin, governor, operator, automation, relayer, organizer, participant1, participant2, winner] = await ethers.getSigners();

  // 1. Получаем ранее развернутые контракты
  const registry = await ethers.getContractAt('Registry', '0x...'); // Укажите адрес развернутого Registry
  const moduleId = keccak256(toUtf8Bytes('Contest'));

  // 2. Получаем фабрику конкурсов
  const factoryAddress = await registry.getModuleServiceByAlias(moduleId, 'ContestFactory');
  const factory = await ethers.getContractAt('ContestFactory', factoryAddress);

  // 3. Создание нового конкурса
  console.log('\n=== Создание нового конкурса ===');

  // Токен для награды
  const usdcToken = '0x...'; // Адрес USDC токена

  // Подготовка призов
  const prizeAmount1 = ethers.parseUnits('500', 6); // 500 USDC
  const prizeAmount2 = ethers.parseUnits('300', 6); // 300 USDC
  const prizeAmount3 = ethers.parseUnits('200', 6); // 200 USDC

  // Получаем PrizeType.MONETARY
  const PrizeType = {
    MONETARY: 0,
    PROMO: 1
  };

  const prizes = [
    {
      prizeType: PrizeType.MONETARY,
      token: usdcToken,
      amount: prizeAmount1,
      recipient: ethers.ZeroAddress // Будет назначен позже
    },
    {
      prizeType: PrizeType.MONETARY,
      token: usdcToken,
      amount: prizeAmount2,
      recipient: ethers.ZeroAddress
    },
    {
      prizeType: PrizeType.MONETARY,
      token: usdcToken,
      amount: prizeAmount3,
      recipient: ethers.ZeroAddress
    },
    {
      prizeType: PrizeType.PROMO,
      token: ethers.ZeroAddress,
      amount: 0,
      recipient: ethers.ZeroAddress
    }
  ];

  // Метаданные конкурса
  const metadata = toUtf8Bytes(JSON.stringify({
    title: 'Конкурс разработчиков',
    description: 'Разработка лучшего смарт-контракта для DeFi приложения',
    rules: 'Участники должны создать смарт-контракт, который...',
    deadline: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString() // 30 дней
  }));

  // Одобряем USDC для использования фабрикой
  const usdc = await ethers.getContractAt('MockERC20', usdcToken);
  const organizerUsdc = usdc.connect(organizer);
  const totalPrize = prizeAmount1.add(prizeAmount2).add(prizeAmount3);
  await executeTransaction(organizerUsdc, 'approve', [factoryAddress, totalPrize]);

  // Создаем конкурс от имени организатора
  const organizerFactory = factory.connect(organizer);
  const tx = await executeTransaction(organizerFactory, 'createContest', [prizes, metadata]);

  // Получаем адрес эскроу из события
  const receipt = await tx.wait();
  let escrowAddress;
  // Здесь должна быть логика для извлечения адреса эскроу из события
  // В реальном сценарии мы бы использовали:
  // escrowAddress = receipt.events[0].args.escrowAddress;
  escrowAddress = '0x...'; // Для демо-сценария предположим, что мы получили адрес

  console.log(`Конкурс создан организатором ${organizer.address} с эскроу ${escrowAddress}`);

  // 4. Получение информации о конкурсе
  const escrow = await ethers.getContractAt('ContestEscrow', escrowAddress);

  const deadline = await escrow.deadline();
  const creator = await escrow.creator();
  const prizesCount = await escrow.getPrizesCount();

  console.log('\n=== Информация о конкурсе ===');
  console.log(`Адрес эскроу: ${escrowAddress}`);
  console.log(`Организатор: ${creator}`);
  console.log(`Срок завершения: ${new Date(Number(deadline) * 1000).toLocaleString()}`);
  console.log(`Количество призов: ${prizesCount}`);

  // 5. Финализация конкурса и распределение призов
  console.log('\n=== Финализация конкурса ===');

  // Назначаем победителей
  const winners = [
    winner.address,
    participant1.address,
    participant2.address,
    participant1.address // Для промо-приза
  ];

  // Организатор финализирует конкурс
  const organizerEscrow = escrow.connect(organizer);
  await executeTransaction(organizerEscrow, 'finalize', [winners]);

  console.log(`Конкурс финализирован, победители назначены`);

  // 6. Проверка состояния призов после финализации
  console.log('\n=== Статус призов ===');

  for (let i = 0; i < prizesCount; i++) {
    const prize = await escrow.getPrize(i);
    console.log(`Приз #${i + 1}:`);
    console.log(`  Тип: ${prize.prizeType === PrizeType.MONETARY ? 'Денежный' : 'Промо'}`);
    console.log(`  Получатель: ${prize.recipient}`);
    if (prize.prizeType === PrizeType.MONETARY) {
      console.log(`  Сумма: ${ethers.formatUnits(prize.amount, 6)} USDC`);
    }
  }

  // 7. Получение приза победителем
  console.log('\n=== Получение приза победителем ===');

  const winnerEscrow = escrow.connect(winner);
  await executeTransaction(winnerEscrow, 'claimPrize', [0]); // Первый приз

  // Проверяем баланс победителя
  const winnerBalance = await usdc.balanceOf(winner.address);
  console.log(`Победитель получил ${ethers.formatUnits(prizeAmount1, 6)} USDC`);
  console.log(`Текущий баланс USDC победителя: ${ethers.formatUnits(winnerBalance, 6)}`);

  console.log('\n=== Демонстрация конкурсов завершена ===');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
