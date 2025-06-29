import { ethers } from "hardhat";
import fs from "fs";
import path from "path";
import type { Contract } from "ethers";
import { artifacts } from "hardhat";

/**
 * Типы основных контрактов системы
 */
export interface SystemContracts {
  access: Contract;
  registry: Contract;
  feeManager: Contract;
  gateway: Contract;
  tokenValidator: Contract;
  marketplaceFactory?: Contract;
  contestFactory?: Contract;
}

/**
 * Константы для таймаутов и повторов
 */
export const RETRY_TIMEOUT = 2000; // мс
export const MAX_RETRIES = 3;

/**
 * Загружает контракт по адресу
 * @param name Имя контракта
 * @param address Адрес контракта
 */
export async function loadContract(name: string, address: string): Promise<Contract> {
  const artifact = await artifacts.readArtifact(name);
  const signer = await ethers.provider.getSigner();
  return new ethers.Contract(address, artifact.abi, signer);
}

/**
 * Интерфейс для хранения деплоев
 */
export interface DeploymentData {
  contracts: {
    access: string;
    registry: string;
    feeManager: string;
    gateway: string;
    tokenValidator: string;
    marketplaceFactory?: string;
    contestFactory?: string;
  };
  timestamp: number;
  network: string;
}

/**
 * Загружает последний деплой из файла
 * @param network Имя сети
 */
export function loadLatestDeployment(network: string = "localhost"): DeploymentData | null {
  const deploymentsDir = path.join(__dirname, "../../deployments");
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
  return JSON.parse(fs.readFileSync(deploymentFile, "utf8"));
}

/**
 * Сохраняет информацию о деплое в файл
 * @param contracts Объект с адресами контрактов
 * @param network Имя сети
 */
export function saveDeployment(contracts: DeploymentData['contracts'], network: string = "localhost"): void {
  const deploymentsDir = path.join(__dirname, "../../deployments");
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, {recursive: true});
  }

  const data: DeploymentData = {
    contracts,
    timestamp: Date.now(),
    network
  };

  const deploymentFile = path.join(deploymentsDir, `${network}-${data.timestamp}.json`);
  fs.writeFileSync(deploymentFile, JSON.stringify(data, null, 2));
  console.log(`Информация о деплое сохранена в ${deploymentFile}`);
}

/**
 * Возвращает контракты системы по последнему деплою
 * @param network Имя сети
 */
export async function getSystemContracts(network: string = "localhost"): Promise<SystemContracts> {
  const deployData = loadLatestDeployment(network);
  if (!deployData) {
    throw new Error(`Не найден деплой для сети ${network}`);
  }

  const contracts = deployData.contracts;
  return {
    access: await loadContract("AccessControlCenter", contracts.access),
    registry: await loadContract("Registry", contracts.registry),
    feeManager: await loadContract("CoreFeeManager", contracts.feeManager),
    gateway: await loadContract("PaymentGateway", contracts.gateway),
    tokenValidator: await loadContract("MultiValidator", contracts.tokenValidator),
    marketplaceFactory: contracts.marketplaceFactory ? await loadContract("MarketplaceFactory", contracts.marketplaceFactory) : undefined,
    contestFactory: contracts.contestFactory ? await loadContract("ContestFactory", contracts.contestFactory) : undefined
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

/**
 * Утилита повторения запросов при ошибках сети
 */
export async function withRetry<T>(fn: () => Promise<T>, onErrorCallback?: (error: Error, attempt: number) => Promise<void>): Promise<T> {
  let lastError: Error = new Error('Неизвестная ошибка');
  for (let i = 0; i < MAX_RETRIES; i++) {
    try {
      return await fn();
    } catch (error) {
      const typedError = error as Error;
      console.warn(`Попытка ${i + 1} не удалась, повторяем через ${RETRY_TIMEOUT}мс...`);
      lastError = typedError;
      if (onErrorCallback) await onErrorCallback(typedError, i);
      await new Promise(resolve => setTimeout(resolve, RETRY_TIMEOUT));
    }
  }
  console.error('Все попытки исчерпаны, последняя ошибка:', lastError);
  return Promise.reject(lastError);
}

/**
 * Получает сервис модуля по алиасу из реестра
 * @param registry Контракт реестра
 * @param moduleId ID модуля
 * @param serviceAlias Алиас сервиса
 */
export async function getModuleServiceByAlias(registry: Contract, moduleId: string, serviceAlias: string): Promise<string> {
  console.log(`Получение сервиса '${serviceAlias}' для модуля ${moduleId}...`);

  try {
    // Проверяем, существует ли модуль
    try {
      const [moduleAddress] = await registry.getFeature(moduleId);
      if (moduleAddress === ethers.ZeroAddress) {
        console.log(`Модуль с ID ${moduleId} не зарегистрирован в реестре`);
        return ethers.ZeroAddress;
      }
      console.log(`Модуль ${moduleId} найден по адресу ${moduleAddress}`);
    } catch (e) {
      console.log(`Ошибка при проверке модуля ${moduleId}:`, e);
      // Продолжаем, так как модуль может быть зарегистрирован позже
    }

    let result = ethers.ZeroAddress;
    let successMethod = '';

    // Пробуем все возможные методы получения сервиса
    const methods = [
      {name: 'getModuleServiceByAlias(bytes32,string)', bytesType: false},
      {name: 'getModuleService(bytes32,string)', bytesType: false},
      {name: 'getModuleService(bytes32,bytes32)', bytesType: true}
    ];

    for (const method of methods) {
      try {
        console.log(`Пробуем метод ${method.name}...`);
        if (!method.bytesType) {
          // Метод принимает строку
          const res = await registry.getFunction(method.name).staticCall(moduleId, serviceAlias);
          if (res && res !== ethers.ZeroAddress) {
            result = res;
            successMethod = method.name;
            break;
          }
        } else {
          // Метод принимает bytes32
          // Конвертируем строку в bytes32 если нужно
          const aliasBytes32 = ethers.keccak256(ethers.toUtf8Bytes(serviceAlias));
          const res = await registry.getFunction(method.name).staticCall(moduleId, aliasBytes32);
          if (res && res !== ethers.ZeroAddress) {
            result = res;
            successMethod = method.name;
            break;
          }
        }
      } catch (methodError) {
        const err = methodError as Error;
        console.log(`Метод ${method.name} не сработал:`, err.message);
        // Продолжаем со следующим методом
      }
    }

    if (result !== ethers.ZeroAddress) {
      console.log(`Успешно получен сервис '${serviceAlias}' через метод ${successMethod}: ${result}`);
    } else {
      console.log(`Не удалось получить сервис '${serviceAlias}' для модуля ${moduleId}`);
    }

    return result;
  } catch (error) {
    console.log(`Общая ошибка при получении сервиса '${serviceAlias}' для модуля ${moduleId}:`, error);
    return ethers.ZeroAddress;
  }
}

/**
 * Извлекает адрес созданного объекта из событий транзакции
 * @param receipt Чек транзакции
 * @param eventName Имя события
 * @param eventSignature Сигнатура события
 * @param addressIndex Индекс адреса в аргументах события
 */
export function getAddressFromEvents(
    receipt: any,
    eventName: string,
    eventSignature: string,
    addressIndex: number = 1
): string | null {
  try {
    // Проверяем, что receipt и logs существуют
    if (!receipt || !receipt.logs) {
      console.error('Receipt или logs отсутствуют');
      return null;
    }

    // Сначала ищем событие по имени фрагмента
    const ev = receipt.logs.find((l: any) => {
      try {
        return l.fragment && l.fragment.name === eventName;
      } catch (e) {
        return false;
      }
    });

    if (ev?.args?.[addressIndex]) {
      return ev.args[addressIndex];
    }

    // Если не нашли через фрагмент, пробуем анализировать topics
    for (const log of receipt?.logs || []) {
      if (log.topics && log.topics[0] === ethers.id(eventSignature)) {
        const iface = new ethers.Interface([`event ${eventSignature}`]);
        const decoded = iface.parseLog({topics: log.topics, data: log.data});
        if (decoded?.args) {
          const values = Object.values(decoded.args);
          if (values.length > addressIndex && typeof values[addressIndex] === 'string') {
            return values[addressIndex];
          }
        }
      }
    }

    return null;
  } catch (e) {
    console.error(`Ошибка при извлечении адреса из событий:`, e);
    return null;
  }
}
