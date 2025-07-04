import { ethers } from 'hardhat';
import { Contract, keccak256, toUtf8Bytes } from 'ethers';
import { CoreContracts } from './types';
import { deployContract } from './contracts';

/**
 * Разворачивает модуль маркетплейса
 */
export async function deployMarketplaceModule(coreContracts: CoreContracts) {
  console.log('\n=== Развертывание модуля маркетплейса ===');

  // Получаем ID модуля
  const MARKETPLACE_MODULE_ID = keccak256(toUtf8Bytes('Marketplace'));

  // Разворачиваем фабрику маркетплейса
  const marketplaceFactory = await deployContract('MarketplaceFactory', [
    await coreContracts.registry.getAddress(),
    await coreContracts.feeManager.getAddress()
  ]);

  return {
    moduleId: MARKETPLACE_MODULE_ID,
    factory: marketplaceFactory,
    name: 'Marketplace'
  };
}

/**
 * Разворачивает модуль подписок
 */
export async function deploySubscriptionModule(coreContracts: CoreContracts) {
  console.log('\n=== Развертывание модуля подписок ===');

  // Получаем ID модуля
  const SUBSCRIPTION_MODULE_ID = keccak256(toUtf8Bytes('SubscriptionManager'));

  // Разворачиваем фабрику подписок
  const subscriptionFactory = await deployContract('SubscriptionFactory', [
    await coreContracts.registry.getAddress(),
    await coreContracts.feeManager.getAddress()
  ]);

  return {
    moduleId: SUBSCRIPTION_MODULE_ID,
    factory: subscriptionFactory,
    name: 'SubscriptionManager'
  };
}

/**
 * Разворачивает модуль конкурсов
 */
export async function deployContestModule(coreContracts: CoreContracts) {
  console.log('\n=== Развертывание модуля конкурсов ===');

  // Получаем ID модуля
  const CONTEST_MODULE_ID = keccak256(toUtf8Bytes('Contest'));

  // Создаем валидатор для конкурсов
  const contestValidator = await deployContract('ContestValidator');

  // Разворачиваем фабрику конкурсов
  const contestFactory = await deployContract('ContestFactory', [
    await coreContracts.registry.getAddress(),
    await coreContracts.feeManager.getAddress()
  ]);

  return {
    moduleId: CONTEST_MODULE_ID,
    factory: contestFactory,
    validator: contestValidator,
    name: 'Contest'
  };
}
