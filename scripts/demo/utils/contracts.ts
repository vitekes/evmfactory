import { ethers } from 'hardhat';

/**
 * Вспомогательная функция для выполнения транзакций с обработкой ошибок
 * @param contract Контракт
 * @param method Имя метода
 * @param args Аргументы метода
 * @returns Результат транзакции
 */
export async function executeTransaction(contract: Contract, method: string, args: any[] = []) {
  try {
    console.log(`Выполняем ${method} на контракте ${await contract.getAddress()}...`);
    const tx = await contract[method](...args);
    await tx.wait();
    console.log(`Метод ${method} успешно выполнен`);
    return tx;
  } catch (error) {
    console.error(`Ошибка при выполнении ${method}:`, error);
    throw error;
  }
}
import { Contract, ContractFactory } from 'ethers';

/**
 * Помощник для прямого развертывания контрактов без прокси
 * @param name Имя контракта
 * @param args Аргументы конструктора
 * @returns Экземпляр контракта
 */
export async function deployContract<T extends Contract>(name: string, args: any[] = []): Promise<T> {
  console.log(`Разворачиваем контракт ${name} напрямую...`);

  try {
    const Factory = await ethers.getContractFactory(name);
    const instance = await Factory.deploy(...args);
    await instance.waitForDeployment();
    console.log(`${name} развёрнут по адресу: ${await instance.getAddress()}`);
    return instance as T;
  } catch (error) {
    console.error(`Ошибка при развертывании ${name}:`, error);
    throw error;
  }
}

/**
 * Универсальная функция для развертывания контрактов
 * Поддерживает как контракты с методом initialize, так и обычные контракты
 */
export async function deployUUPSProxy<T extends Contract>(name: string, initArgs: any[] = []): Promise<T> {
  console.log(`Разворачиваем контракт ${name}...`);

  // Получаем фабрику контракта
  const Factory = await ethers.getContractFactory(name);

  // Проверяем, есть ли у контракта метод initialize в ABI
  const hasInitializeMethod = Factory.interface.fragments.some(
    (fragment) => fragment.type === 'function' && fragment.name === 'initialize'
  );

  let instance: Contract;

  try {
    // Сначала пробуем простое развертывание и инициализацию
    if (hasInitializeMethod) {
      // Для контрактов с initialize
      console.log(`${name} использует паттерн initialize, деплоим без параметров...`);
      instance = await Factory.deploy();
      await instance.waitForDeployment();
      console.log(`${name} развёрнут по адресу: ${await instance.getAddress()}`);

      try {
        console.log(`Инициализируем ${name}...`);
        const tx = await instance.initialize(...initArgs);
        await tx.wait();
        console.log(`${name} успешно инициализирован`);
      } catch (initError) {
        console.log(`Не удалось инициализировать ${name} - пробуем с конструктором...`);
        // Если не удалось инициализировать, пробуем с параметрами в конструкторе
        instance = await Factory.deploy(...initArgs);
        await instance.waitForDeployment();
        console.log(`${name} развернут через конструктор: ${await instance.getAddress()}`);
      }
    } else {
      // Для обычных контрактов без initialize
      console.log(`${name} не использует паттерн initialize, деплоим с параметрами в конструкторе...`);
      instance = await Factory.deploy(...initArgs);
      await instance.waitForDeployment();
      console.log(`${name} развёрнут по адресу: ${await instance.getAddress()}`);
      return instance as T;
    } catch (error) {
      console.error(`Ошибка при развертывании ${name}:`, error);
      throw error;
    }
    }
}

/**
 * Хелпер для вызова функций контракта с ожиданием выполнения
 */
export async function executeTransaction(contract: Contract, method: string, args: any[] = [], options: any = {}) {
  console.log(`Вызываем ${method} с аргументами:`, args);
  const tx = await contract[method](...args, options);
  await tx.wait();
  return tx;
}
