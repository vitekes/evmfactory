// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './IPaymentComponent.sol';

/// @title IGateway
/// @notice Универсальный интерфейс платежного шлюза для обработки платежей
/// @dev Объединяет все необходимые методы для платежных шлюзов
interface IGateway is IPaymentComponent {
    /// @notice Результаты обработки платежа
    enum PaymentResult {
        FAILED,
        SUCCESS
    }
    /// @notice Универсальный метод обработки платежей
    /// @param moduleId Идентификатор модуля
    /// @param token Адрес токена (address(0) для нативной валюты)
    /// @param amount Сумма платежа (0 если данные в paymentData)
    /// @param paymentData Произвольные данные платежа
    /// @return result Результат обработки
    /// @return paymentId Идентификатор платежа
    /// @return netAmount Чистая сумма после вычета комиссий
    function processPayment(
        bytes32 moduleId,
        address token,
        uint256 amount,
        bytes memory paymentData
    ) external payable returns (PaymentResult result, bytes32 paymentId, uint256 netAmount);

    /// @notice Конвертировать сумму из одной валюты в другую
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

    /// @notice Проверить, поддерживается ли пара токенов
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
    /// @return tokens Список поддерживаемых токенов
    function getSupportedTokens(bytes32 moduleId) external view returns (address[] memory tokens);

    /// @notice Получить статус платежа
    /// @param paymentId Идентификатор платежа
    /// @return status Статус платежа
    function getPaymentStatus(bytes32 paymentId) external view returns (PaymentResult status);

    /// @notice Проверить, активен ли шлюз для модуля
    /// @param moduleId Идентификатор модуля
    /// @return enabled Активен ли шлюз
    function isEnabled(bytes32 moduleId) external view returns (bool enabled);

    /// @notice Добавить процессор в шлюз
    /// @param processor Адрес процессора
    /// @param position Позиция в цепочке (0 - в конец)
    /// @return success Успешность операции
    function addProcessor(address processor, uint256 position) external returns (bool success);

    /// @notice Получить список процессоров для модуля
    /// @param moduleId Идентификатор модуля
    /// @return processors Список процессоров
    function getProcessors(bytes32 moduleId) external view returns (address[] memory processors);
}
