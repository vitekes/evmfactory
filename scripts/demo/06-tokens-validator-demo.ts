import { ethers } from 'hardhat';
import { executeTransaction } from './utils/contracts';

async function main() {
  console.log('=== Демонстрация: Работа с валидатором токенов ===');

  // Получаем аккаунты
  const [admin, governor, operator] = await ethers.getSigners();

  // 1. Получаем ранее развернутые контракты
  const validator = await ethers.getContractAt('MultiValidator', '0x...'); // Укажите адрес развернутого MultiValidator

  // 2. Создание новых тестовых токенов
  console.log('\n=== Создание тестовых токенов ===');

  const TestToken = await ethers.getContractFactory('MockERC20');
  const tokenA = await TestToken.deploy('Token A', 'TKNA', 18);
  const tokenB = await TestToken.deploy('Token B', 'TKNB', 18);
  const tokenC = await TestToken.deploy('Token C', 'TKNC', 18);

  console.log(`Token A развёрнут по адресу: ${await tokenA.getAddress()}`);
  console.log(`Token B развёрнут по адресу: ${await tokenB.getAddress()}`);
  console.log(`Token C развёрнут по адресу: ${await tokenC.getAddress()}`);

  // 3. Добавление токенов в валидатор
  console.log('\n=== Добавление токенов в валидатор ===');

  // Только governor может добавлять токены
  const governorValidator = validator.connect(governor);

  await executeTransaction(governorValidator, 'addToken', [await tokenA.getAddress()]);
  await executeTransaction(governorValidator, 'addToken', [await tokenB.getAddress()]);

  console.log(`Токены A и B добавлены в валидатор`);

  // 4. Проверка статуса токенов
  const isTokenAAllowed = await validator.isAllowed(await tokenA.getAddress());
  const isTokenBAllowed = await validator.isAllowed(await tokenB.getAddress());
  const isTokenCAllowed = await validator.isAllowed(await tokenC.getAddress());

  console.log('\n=== Статус токенов ===');
  console.log(`Token A разрешен: ${isTokenAAllowed}`);
  console.log(`Token B разрешен: ${isTokenBAllowed}`);
  console.log(`Token C разрешен: ${isTokenCAllowed}`);

  // 5. Массовая установка статуса токенов
  console.log('\n=== Массовая установка статуса токенов ===');

  const tokens = [
    await tokenA.getAddress(),
    await tokenB.getAddress(),
    await tokenC.getAddress()
  ];

  // Устанавливаем все токены как разрешенные
  await executeTransaction(governorValidator, 'bulkSetToken', [tokens, true]);

  console.log(`Все токены (включая токен C) теперь разрешены`);

  // 6. Проверка всех токенов
  const areAllTokensAllowed = await validator.areAllowed(tokens);
  console.log(`Все ли токены разрешены: ${areAllTokensAllowed}`);

  // 7. Удаление токена из валидатора
  console.log('\n=== Удаление токена из валидатора ===');

  await executeTransaction(governorValidator, 'removeToken', [await tokenB.getAddress()]);

  const isTokenBStillAllowed = await validator.isAllowed(await tokenB.getAddress());
  console.log(`Token B удален из валидатора, его статус: ${isTokenBStillAllowed ? 'Разрешен' : 'Запрещен'}`);

  // 8. Проверка обновленного списка
  const updatedAreAllTokensAllowed = await validator.areAllowed(tokens);
  console.log(`Все ли токены разрешены после удаления токена B: ${updatedAreAllTokensAllowed ? 'Да' : 'Нет'}`);

  console.log('\n=== Демонстрация валидатора токенов завершена ===');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
