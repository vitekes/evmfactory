import { ethers } from 'hardhat';

/**
 * Утилита для декодирования селекторов ошибок Solidity
 * Использование: npx hardhat run scripts/debug/errorDecoder.ts
 */

async function main() {
  console.log('===== ДЕКОДЕР ОШИБОК SOLIDITY =====');

  const errorSelector = '0xf92ee8a9';
  console.log(`Декодирование ошибки с селектором: ${errorSelector}`);

  // Деплой контракта ErrorMap
  const ErrorMap = await ethers.getContractFactory('ErrorMap');
  const errorMap = await ErrorMap.deploy();
  await errorMap.waitForDeployment();

  // Получение имени ошибки
  const errorName = await errorMap.getErrorName(errorSelector);
  console.log(`Найденная ошибка: ${errorName}`);

  // Для стандартных ошибок OpenZeppelin
  if (errorSelector === '0xf92ee8a9') {
    console.log('\nЭто ошибка "UPGRADEABLE PROXY: ALREADY INITIALIZED"');
    console.log('Причина: Попытка повторно инициализировать прокси-контракт');
    console.log('Решение: Проверьте логику инициализации или используйте upgradeToAndCall для обновления');
  }
}

// Запускаем скрипт
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
