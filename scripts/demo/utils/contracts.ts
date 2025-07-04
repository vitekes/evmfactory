import { ethers } from 'hardhat';
import { Contract } from 'ethers';

/**
 * Выполняет вызов метода контракта и ожидает подтверждения транзакции
 */
export async function executeTransaction(
  contract: Contract,
  method: string,
  args: any[] = [],
  options: any = {}
) {
  console.log(`Вызываем ${method} с аргументами:`, args);
  const tx = await (contract as any)[method](...args, options);
  await tx.wait();
  return tx;
}

/**
 * Помощник для прямого развертывания контрактов без прокси
 */
export async function deployContract<T extends Contract>(
  name: string,
  args: any[] = []
): Promise<T> {
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
 * Универсальная функция для развертывания контрактов с поддержкой initialize
 */
export async function deployUUPSProxy<T extends Contract>(
  name: string,
  initArgs: any[] = []
): Promise<T> {
  console.log(`Разворачиваем контракт ${name}...`);

  const Factory = await ethers.getContractFactory(name);
  const hasInitializeMethod = Factory.interface.fragments.some(
    (f) => f.type === 'function' && f.name === 'initialize'
  );

  let instance: Contract;

  try {
    if (hasInitializeMethod) {
      console.log(`${name} использует паттерн initialize, деплоим без параметров...`);
      instance = await Factory.deploy();
      await instance.waitForDeployment();
      console.log(`${name} развёрнут по адресу: ${await instance.getAddress()}`);

      try {
        const tx = await instance.initialize(...initArgs);
        await tx.wait();
        console.log(`${name} успешно инициализирован`);
      } catch (initError) {
        console.log(
          `Не удалось инициализировать ${name} - пробуем с конструктором...`
        );
        instance = await Factory.deploy(...initArgs);
        await instance.waitForDeployment();
        console.log(`${name} развернут через конструктор: ${await instance.getAddress()}`);
      }
    } else {
      console.log(
        `${name} не использует паттерн initialize, деплоим с параметрами в конструкторе...`
      );
      instance = await Factory.deploy(...initArgs);
      await instance.waitForDeployment();
      console.log(`${name} развёрнут по адресу: ${await instance.getAddress()}`);
    }
    return instance as T;
  } catch (error) {
    console.error(`Ошибка при развертывании ${name}:`, error);
    throw error;
  }
}
