// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IEventRouter {
    enum EventKind {
        Unknown,            // Неизвестный тип (запрещен)
        ListingCreated,     // Создание листинга в маркетплейсе
        SubscriptionCharged,// Оплата подписки
        ContestFinalized,   // Финализация конкурса
        PaymentProcessed,   // Обработка платежа через PaymentGateway
        TokenConverted,     // Конвертация токенов
        SubscriptionCreated,// Создание новой подписки
        MarketplaceSale,    // Продажа NFT в маркетплейсе
        UserRegistered,     // Регистрация нового пользователя
        FeeCollected,       // Сбор комиссии
        FeeWithdrawn,       // Вывод комиссии
        PriceConverted,     // Конвертация цены
        DomainSeparatorUpdated, // Обновление разделителя домена
        ListingRevoked,     // Отзыв листинга
        ContestCreated,     // Создание конкурса
        SubscriptionRenewed,// Продление подписки
        SubscriptionCancelled, // Отмена подписки
        TokenAllowed,       // Токен разрешен для использования
        TokenDenied,        // Токен запрещен для использования
        ServiceRegistered,  // Регистрация сервиса
        FeatureUpgraded     // Обновление функционала
    }

    /// @notice Route an event from a module
    /// @param kind Type of event
    /// @param payload Event data
    function route(EventKind kind, bytes calldata payload) external;
}
