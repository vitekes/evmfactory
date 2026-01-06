// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IPaymentGateway
/// @notice Интерфейс платёжного шлюза — единственной точки входа для платежей
interface IPaymentGateway {
    /// @notice Обработать платеж
    /// @param moduleId Идентификатор модуля
    /// @param token Адрес токена (address(0) для нативной валюты)
    /// @param payer Адрес плательщика
    /// @param amount Сумма платежа
    /// @param signature Подпись, если требуется
    /// @return netAmount Чистая сумма после вычета комиссий
    function processPayment(
        bytes32 moduleId,
        address token,
        address payer,
        uint256 amount,
        bytes calldata signature
    ) external payable returns (uint256 netAmount);

    /// @notice Конвертировать сумму из одного токена в другой
    /// @param moduleId Идентификатор модуля
    /// @param fromToken Токен источник
    /// @param toToken Токен назначения
    /// @param amount Сумма для конвертации
    /// @return convertedAmount Сконвертированная сумма
    function convertAmount(
        bytes32 moduleId,
        address fromToken,
        address toToken,
        uint256 amount
    ) external view returns (uint256 convertedAmount);

    /// @notice Проверить поддержку пары токенов
    /// @param moduleId Идентификатор модуля
    /// @param fromToken Токен источник
    /// @param toToken Токен назначения
    /// @return isSupported Поддерживается ли пара
    function isPairSupported(
        bytes32 moduleId,
        address fromToken,
        address toToken
    ) external view returns (bool isSupported);

    /// @notice Получить список поддерживаемых токенов
    /// @param moduleId Идентификатор модуля
    /// @return tokens Список токенов
    function getSupportedTokens(bytes32 moduleId) external view returns (address[] memory tokens);

    /// @notice Получить статус платежа по идентификатору
    /// @param paymentId Идентификатор платежа
    /// @return status Статус платежа
    function getPaymentStatus(bytes32 paymentId) external view returns (uint8 status);
}
