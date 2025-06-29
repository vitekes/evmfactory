import { ethers } from "hardhat";
import fs from "fs";
import path from "path";

/**
 * Типы основных контрактов системы
 */
export interface SystemContracts {
  access: string;
  registry: string;
  feeManager: string;
  gateway: string;
  tokenValidator: string;
  marketplaceFactory: string;
}

/**
 * Константы модулей и сервисов
 */
export const CONSTANTS = {
  // Сервисы core для getCoreService (bytes32)
  ACCESS_SERVICE: ethers.keccak256(ethers.toUtf8Bytes("AccessControlCenter")),

  // Строковые алиасы для getModuleService(bytes32,string)
  PAYMENT_GATEWAY_ALIAS: "PaymentGateway",
  VALIDATOR_ALIAS: "Validator",

  // Прежние константы (bytes32) - поддерживаем для обратной совместимости
  PAYMENT_GATEWAY_SERVICE: ethers.keccak256(ethers.toUtf8Bytes("PaymentGateway")),
  VALIDATOR_SERVICE: ethers.keccak256(ethers.toUtf8Bytes("Validator")),

  // ID модулей (bytes32)
  MARKETPLACE_ID: ethers.keccak256(ethers.toUtf8Bytes("Marketplace")),
  CONTEST_ID: ethers.keccak256(ethers.toUtf8Bytes("Contest")),
  FACTORY_ADMIN: ethers.keccak256(ethers.toUtf8Bytes("FACTORY_ADMIN")),
};

/**
 * Загружает контракт по адресу
 * @param name Имя контракта
 * @param address Адрес контракта
 */
export async function loadContract(name: string, address: string) {
  const Contract = await ethers.getContractFactory(name);
  return Contract.attach(address);
}

/**
 * Загружает последний деплой из файла
 * @param network Имя сети
 */
export function loadLatestDeployment(network: string = "localhost"): SystemContracts | null {
  const deploymentsDir = path.join(__dirname, "../deployments");
  if (!fs.existsSync(deploymentsDir)) {
    return null;
  }

  const files = fs.readdirSync(deploymentsDir)
    .filter(file => file.startsWith(`${network}-`) && file.endsWith(".json"))
    .sort()
    .reverse(); // Сортируем в обратном порядке, чтобы получить самый последний файл

  if (files.length === 0) {
    return null;
  }

  const deploymentFile = path.join(deploymentsDir, files[0]);
  const deploymentData = JSON.parse(fs.readFileSync(deploymentFile, "utf8"));
  return deploymentData.contracts;
}

/**
 * Возвращает контракты системы по последнему деплою
 * @param network Имя сети
 */
export async function getSystemContracts(network: string = "localhost") {
  const contracts = loadLatestDeployment(network);
  if (!contracts) {
    throw new Error(`Не найден деплой для сети ${network}`);
  }

  return {
    access: await loadContract("AccessControlCenter", contracts.access),
    registry: await loadContract("Registry", contracts.registry),
    feeManager: await loadContract("CoreFeeManager", contracts.feeManager),
    gateway: await loadContract("PaymentGateway", contracts.gateway),
    tokenValidator: await loadContract("MultiValidator", contracts.tokenValidator),
    marketplaceFactory: await loadContract("MarketplaceFactory", contracts.marketplaceFactory)
  };
}

/**
 * Вспомогательная функция для безопасного выполнения операций
 */
export async function safeExecute<T>(operation: string, fn: () => Promise<T>, defaultValue?: T): Promise<T> {
  try {
    console.log(`Выполнение: ${operation}...`);
    const result = await fn();
    console.log(`Успешно: ${operation}`);
    return result;
  } catch (error) {
    const typedError = error as Error;
    console.error(`Ошибка при выполнении ${operation}:`, typedError);
    if (defaultValue !== undefined) {
      console.log(`Используем значение по умолчанию для ${operation}`);
      return defaultValue;
    }
    throw error;
  }
}
