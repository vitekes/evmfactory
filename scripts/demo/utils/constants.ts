import { ethers } from "hardhat";

/**
 * Константы модулей и сервисов для использования в демо-скриптах
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

    // ID модулей (bytes32) - совпадают с идентификаторами в CoreDefs.sol
    MARKETPLACE_ID: ethers.keccak256(ethers.toUtf8Bytes("Marketplace")),
    MARKETPLACE_MODULE_ID: ethers.keccak256(ethers.toUtf8Bytes("Marketplace")), // Дублируем для ясности
    CONTEST_ID: ethers.keccak256(ethers.toUtf8Bytes("Contest")),  // Должен соответствовать CoreDefs.CONTEST_MODULE_ID
    SUBSCRIPTION_ID: ethers.keccak256(ethers.toUtf8Bytes("Subscription")),
    SUBSCRIPTION_MODULE_ID: ethers.keccak256(ethers.toUtf8Bytes("Subscription")),
    FACTORY_ADMIN: ethers.keccak256(ethers.toUtf8Bytes("FACTORY_ADMIN")), // Должен совпадать с BaseFactory.FACTORY_ADMIN
    // Альтернативный вариант, если оригинальный не сработает - для отладки
    FACTORY_ADMIN_ALT: "0x" + ethers.keccak256(ethers.toUtf8Bytes("FACTORY_ADMIN")).substring(2).toLowerCase(),
    MODULE_ADMIN: ethers.keccak256(ethers.toUtf8Bytes("MODULE_ADMIN"))
};

/**
 * Типы призов в системе конкурсов
 */
export enum PrizeType {
    MONETARY = 0,
    PROMO = 1
}

/**
 * Константы для имен ролей в системе доступа
 */
export const ROLES = {
    FEATURE_OWNER: "FEATURE_OWNER_ROLE",
    GOVERNOR: "GOVERNOR_ROLE",
    DEFAULT_ADMIN: "DEFAULT_ADMIN_ROLE",
    MODULE: "MODULE_ROLE",
    FACTORY_ADMIN: "FACTORY_ADMIN"
};
