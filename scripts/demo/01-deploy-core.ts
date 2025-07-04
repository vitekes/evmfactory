import { ethers } from 'hardhat';
import { deployCore, setupCoreConnections, setupRoles, setupTestTokens } from './utils/system';

async function main() {
  console.log('=== Демонстрация: Развертывание и настройка ядра системы ===');

  // Получаем аккаунты для демонстрации
  const [admin, governor, operator, automation, relayer, user1, user2] = await ethers.getSigners();

  // Выводим информацию об используемых аккаунтах
  console.log('\n=== Используемые аккаунты ===');
  console.log(`Администратор: ${admin.address}`);
  console.log(`Управляющий токенами: ${governor.address}`);
  console.log(`Оператор: ${operator.address}`);
  console.log(`Автоматизация: ${automation.address}`);
  console.log(`Релейер: ${relayer.address}`);
  console.log(`Пользователь 1: ${user1.address}`);
  console.log(`Пользователь 2: ${user2.address}`);

  // 1. Развертывание ядра системы
  const coreContracts = await deployCore();

  // 2. Настройка связей между контрактами
  await setupCoreConnections(coreContracts);

  // 3. Настройка ролей для аккаунтов
  const accounts = {
    admin: admin.address,
    governor: governor.address,
    operator: operator.address,
    automation: automation.address,
    relayer: relayer.address,
    user1: user1.address,
    user2: user2.address
  };
  await setupRoles(coreContracts, accounts);

  // 4. Настройка тестовых токенов
  const tokens = await setupTestTokens(coreContracts, governor.address);

  console.log('\n=== Ядро системы успешно развернуто и настроено ===');
  console.log('Перейдите к следующему скрипту для развертывания модулей');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
