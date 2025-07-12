// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;


/// @title IPaymentProcessor
/// @notice Интерфейс отдельного процессора платежей
interface IPaymentProcessor {
    enum ProcessResult {
        SUCCESS,
        FAILED,
        SKIPPED
    }

    /// @notice Проверить применимость процессора к контексту
    /// @param contextBytes Сериализованный контекст платежа
    /// @return applicable Применим ли процессор
    function isApplicable(bytes calldata contextBytes) external view returns (bool applicable);

    /// @notice Обработать платеж
    /// @param contextBytes Сериализованный контекст платежа
    /// @return result Результат обработки
    /// @return updatedContextBytes Обновлённый сериализованный контекст
    function process(bytes calldata contextBytes) external returns (ProcessResult result, bytes memory updatedContextBytes);

    /// @notice Получить имя процессора
    /// @return name Имя процессора
    function getName() external pure returns (string memory name);

    /// @notice Получить версию процессора
    /// @return version Версия процессора
    function getVersion() external pure returns (string memory version);

    /// @notice Настроить процессор для модуля
    /// @param moduleId Идентификатор модуля
    /// @param configData Конфигурационные данные
    function configure(bytes32 moduleId, bytes calldata configData) external;
}
