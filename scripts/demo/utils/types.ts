import { Contract } from 'ethers';

/**
 * Основные контракты системы
 */
export interface CoreContracts {
  accessControl: Contract; // Управление доступом
  registry: Contract;      // Реестр сервисов и модулей
  eventRouter: Contract;   // Маршрутизатор событий
  feeManager: Contract;    // Управление комиссиями
  validator: Contract;     // Валидатор токенов
  priceOracle: Contract;   // Оракул цен
  paymentGateway: Contract; // Платежный шлюз
}

/**
 * Основные роли в системе
 */
export interface SystemRoles {
  DEFAULT_ADMIN_ROLE: string;
  FEATURE_OWNER_ROLE: string;
  OPERATOR_ROLE: string;
  RELAYER_ROLE: string;
  MODULE_ROLE: string;
  AUTOMATION_ROLE: string;
  GOVERNOR_ROLE: string;
  FACTORY_ADMIN: string;
}

/**
 * Аккаунты системы
 */
export interface SystemAccounts {
  admin: string;       // Администратор системы
  governor: string;    // Управляющий токенами
  operator: string;    // Оператор для повседневных операций
  automation: string;  // Автоматизированный аккаунт (bot)
  relayer: string;     // Релейер для подписанных транзакций
  user1: string;       // Обычный пользователь 1
  user2: string;       // Обычный пользователь 2
}

/**
 * Настройки модулей
 */
export interface ModuleSettings {
  moduleId: string;    // Идентификатор модуля
  name: string;        // Название модуля
  factoryAddress?: string; // Адрес фабрики модуля (если есть)
  validator?: Contract; // Валидатор для модуля
  services: {[key: string]: string}; // Сервисы модуля (алиас -> адрес)
}
