// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IFeeManager
/// @notice Интерфейс менеджера комиссий для обработки платежей
interface IFeeManager {
    /// @notice Устанавливает процентную комиссию для модуля и токена
    /// @param moduleId Идентификатор модуля
    /// @param token Адрес токена
    /// @param feeBps Комиссия в базисных пунктах (1/100 процента)
    function setPercentFee(bytes32 moduleId, address token, uint16 feeBps) external;

    /// @notice Устанавливает фиксированную комиссию для модуля и токена
    /// @param moduleId Идентификатор модуля
    /// @param token Адрес токена
    /// @param amount Фиксированная сумма комиссии
    function setFixedFee(bytes32 moduleId, address token, uint256 amount) external;

    /// @notice Рассчитывает комиссию для указанной суммы
    /// @param moduleId Идентификатор модуля
    /// @param token Адрес токена
    /// @param amount Сумма платежа
    /// @return feeAmount Сумма комиссии
    function calculateFee(bytes32 moduleId, address token, uint256 amount) external view returns (uint256 feeAmount);

    /// @notice Рассчитывает чистую сумму после вычета комиссии
    /// @param moduleId Идентификатор модуля
    /// @param token Адрес токена
    /// @param amount Исходная сумма
    /// @return netAmount Чистая сумма после вычета комиссии
    function calculateNetAmount(
        bytes32 moduleId,
        address token,
        uint256 amount
    ) external view returns (uint256 netAmount);

    /// @notice Вносит комиссию в систему
    /// @param moduleId Идентификатор модуля
    /// @param token Адрес токена
    /// @param amount Сумма комиссии
    function depositFee(bytes32 moduleId, address token, uint256 amount) external;

    /// @notice Собирает комиссию с платежа
    /// @param moduleId Идентификатор модуля
    /// @param token Адрес токена
    /// @param amount Сумма платежа
    /// @return feeAmount Фактически собранная комиссия
    function collect(bytes32 moduleId, address token, uint256 amount) external returns (uint256 feeAmount);

    /// @notice Обрабатывает платеж с комиссией
    /// @param moduleId Идентификатор модуля
    /// @param token Адрес токена
    /// @param payer Адрес плательщика
    /// @param amount Сумма платежа
    /// @return feeAmount Сумма комиссии
    function processFee(
        bytes32 moduleId,
        address token,
        address payer,
        uint256 amount
    ) external returns (uint256 feeAmount);

    /// @notice Выводит собранные комиссии
    /// @param moduleId Идентификатор модуля
    /// @param token Адрес токена
    /// @param to Адрес получателя
    function withdrawFees(bytes32 moduleId, address token, address to) external;

    /// @notice Собирает накопленные комиссии за токен
    /// @param token Адрес токена для сбора комиссий
    /// @param recipient Адрес получателя комиссий
    function collectFees(address token, address recipient) external;

    /// @notice Устанавливает адрес с нулевой комиссией
    /// @param moduleId Идентификатор модуля
    /// @param user Адрес пользователя
    /// @param status Статус нулевой комиссии
    function setZeroFeeAddress(bytes32 moduleId, address user, bool status) external;

    /// @notice Устанавливает адрес центра управления доступом
    /// @param newAccess Новый адрес центра управления доступом
    function setAccessControl(address newAccess) external;

    /// @notice Устанавливает адрес реестра
    /// @param newRegistry Новый адрес реестра
    function setRegistry(address newRegistry) external;

    /// @notice Приостанавливает сбор комиссий
    function pause() external;

    /// @notice Возобновляет сбор комиссий
    function unpause() external;
}
