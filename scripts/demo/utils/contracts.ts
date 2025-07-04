import { ethers } from 'hardhat';
import { Contract } from 'ethers';

/**
 * Помощник для прямого развертывания контрактов без прокси
 */
export async function deployContract<T extends Contract>(name: string, args: any[] = []): Promise<T> {
  console.log(`Разворачиваем контракт ${name} напрямую...`);
  const Factory = await ethers.getContractFactory(name);
  const instance = await Factory.deploy(...args);
  await instance.waitForDeployment();
  console.log(`${name} развёрнут по адресу: ${await instance.getAddress()}`);
  return instance as T;
}

/**
 * Универсальная функция для развертывания контрактов, поддерживающая initialize
 */
export async function deployUUPSProxy<T extends Contract>(name: string, initArgs: any[] = []): Promise<T> {
  console.log(`Разворачиваем контракт ${name}...`);
  const Factory = await ethers.getContractFactory(name);
  const hasInitializeMethod = Factory.interface.fragments.some(
    (f) => f.type === 'function' && f.name === 'initialize'
  );

  let instance: Contract;

  if (hasInitializeMethod) {
    instance = await Factory.deploy();
    await instance.waitForDeployment();
    console.log(`${name} развёрнут по адресу: ${await instance.getAddress()}`);

    try {
      const tx = await instance.initialize(...initArgs);
      await tx.wait();
      console.log(`${name} успешно инициализирован`);
    } catch (initError) {
      console.log(`Не удалось инициализировать ${name} - пробуем с конструктором...`);
      instance = await Factory.deploy(...initArgs);
      await instance.waitForDeployment();
      console.log(`${name} развернут через конструктор: ${await instance.getAddress()}`);
    }
  } else {
    instance = await Factory.deploy(...initArgs);
    await instance.waitForDeployment();
    console.log(`${name} развёрнут по адресу: ${await instance.getAddress()}`);
  }

  return instance as T;
}

/**
 * Хелпер для вызова функций контракта с ожиданием выполнения
 */
export async function executeTransaction(
  contract: Contract,
  method: string,
  args: any[] = [],
  options: any = {}
) {
  try {
    console.log(`Вызываем ${method} с аргументами:`, args);
    const tx = await contract[method](...args, options);
    await tx.wait();
    console.log(`Метод ${method} успешно выполнен`);
    return tx;
  } catch (error) {
    console.error(`Ошибка при выполнении ${method}:`, error);
    throw error;
  }
}
