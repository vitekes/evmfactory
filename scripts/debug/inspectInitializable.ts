import { ethers } from 'hardhat';

/**
 * Утилита для проверки статуса инициализации контрактов
 * Использование: npx hardhat run scripts/debug/inspectInitializable.ts
 */

async function main() {
  console.log('===== ИНСПЕКТОР СТАТУСА ИНИЦИАЛИЗАЦИИ =====');

  if (process.argv.length < 3) {
    console.log('Использование: npx hardhat run scripts/debug/inspectInitializable.ts -- АДРЕС_КОНТРАКТА');
    return;
  }

  // Получаем адрес контракта из аргументов командной строки
  const contractAddress = process.argv[2];
  console.log(`Проверка статуса инициализации контракта: ${contractAddress}`);

  // Проверяем storage slot 0, где хранится статус инициализации
  const storageSlot0 = await ethers.provider.getStorage(contractAddress, 0);
  console.log('Storage slot 0:', storageSlot0);

  // Конвертируем в BigInt для удобства анализа
  const value = ethers.toBigInt(storageSlot0);

  // Извлекаем младший байт (_initialized) и следующий байт (_initializing)
  const initialized = value & 0xFFn;
  const initializing = (value >> 8n) & 0x1n;

  console.log('_initialized:', initialized.toString());
  console.log('_initializing:', initializing.toString());

  // Интерпретация значений
  console.log('\nСтатус инициализации:');
  if (initialized === 0n) {
    console.log('Контракт НЕ ИНИЦИАЛИЗИРОВАН');
  } else if (initialized === 1n) {
    console.log('Контракт ИНИЦИАЛИЗИРОВАН (версия 1)');
  } else if (initialized > 1n) {
    console.log(`Контракт ИНИЦИАЛИЗИРОВАН (версия ${initialized})`);
  }

  if (initializing === 1n) {
    console.log('Контракт В ПРОЦЕССЕ ИНИЦИАЛИЗАЦИИ');
  }
}

// Запускаем скрипт
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
