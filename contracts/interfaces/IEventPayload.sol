// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IEventPayload
/// @notice Определяет стандартную структуру полезной нагрузки для событий системы
/// @dev Используется для обеспечения совместимости формата данных событий
interface IEventPayload {
    /// @notice Структура для событий, связанных с регистрацией сервисов
    /// @param serviceId Идентификатор сервиса
    /// @param serviceAddress Адрес сервиса
    /// @param moduleId Идентификатор модуля (если применимо)
    /// @param version Версия события (для совместимости)
    struct ServiceEvent {
        bytes32 serviceId;
        address serviceAddress;
        bytes32 moduleId;
        uint16 version;
    }

    /// @notice Структура для событий листинга маркетплейса
    /// @param sku Идентификатор товара
    /// @param seller Адрес продавца
    /// @param buyer Адрес покупателя (если применимо)
    /// @param price Цена в базовой валюте
    /// @param paymentToken Токен оплаты
    /// @param paymentAmount Сумма оплаты
    /// @param timestamp Временная метка события
    /// @param listingHash Хеш листинга
    /// @param version Версия события
    struct MarketplaceEvent {
        bytes32 sku;
        address seller;
        address buyer;
        uint256 price;
        address paymentToken;
        uint256 paymentAmount;
        uint256 timestamp;
        bytes32 listingHash;
        uint16 version;
    }

    /// @notice Структура для событий токенов
    /// @param tokenAddress Адрес токена
    /// @param fromToken Исходный токен (для конвертации)
    /// @param toToken Целевой токен (для конвертации)
    /// @param amount Сумма
    /// @param convertedAmount Конвертированная сумма
    /// @param version Версия события
    struct TokenEvent {
        address tokenAddress;
        address fromToken;
        address toToken;
        uint256 amount;
        uint256 convertedAmount;
        uint16 version;
    }

    /// @notice Структура для событий конкурсов
    /// @param creator Создатель конкурса
    /// @param escrowAddress Адрес эскроу-контракта
    /// @param deadline Срок завершения конкурса
    /// @param version Версия события
    struct ContestEvent {
        address creator;
        address escrowAddress;
        uint256 deadline;
        uint16 version;
    }

    /// @notice Структура для событий подписок
    /// @param subscriber Подписчик
    /// @param planId Идентификатор плана подписки
    /// @param startTime Время начала подписки
    /// @param endTime Время окончания подписки
    /// @param token Токен оплаты
    /// @param amount Сумма
    /// @param version Версия события
    struct SubscriptionEvent {
        address subscriber;
        bytes32 planId;
        uint256 startTime;
        uint256 endTime;
        address token;
        uint256 amount;
        uint16 version;
    }

    /// @notice Структура для событий обновления функциональности
    /// @param featureId Идентификатор функции
    /// @param oldImplementation Старая реализация
    /// @param newImplementation Новая реализация
    /// @param context Контекст функции
    /// @param version Версия события
    struct FeatureEvent {
        bytes32 featureId;
        address oldImplementation;
        address newImplementation;
        uint8 context;
        uint16 version;
    }
}
