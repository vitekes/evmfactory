// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './IPaymentComponent.sol';

/// @title IPaymentProcessor
/// @notice Интерфейс для обработчиков платежей
/// @dev Каждый обработчик в цепочке должен реализовывать этот интерфейс
interface IPaymentProcessor is IPaymentComponent {
    /// @notice Возможные результаты обработки процессором
    enum ProcessResult {
        FAILED,
        SUCCESS,
        SKIPPED,
        MODIFIED
    }
    /// @notice Обработать контекст платежа
    /// @param context Контекст платежа
    /// @return result Результат обработки
    /// @return updatedContext Обновленный контекст
    function process(bytes memory context) external returns (ProcessResult result, bytes memory updatedContext);

    // Методы getName() и getVersion() унаследованы от IPaymentComponent

    /// @notice Проверить, активен ли процессор
    /// @param moduleId Идентификатор модуля
    /// @return enabled Активен ли процессор для модуля
    function isEnabled(bytes32 moduleId) external view returns (bool enabled);

    /// @notice Настроить процессор для модуля
    /// @param moduleId Идентификатор модуля
    /// @param config Конфигурация в виде байтов
    /// @return success Успешность настройки
    function configure(bytes32 moduleId, bytes calldata config) external returns (bool success);

    /// @notice Проверить, применим ли процессор к контексту
    /// @param context Контекст платежа
    /// @return applicable Применим ли процессор
    function isApplicable(bytes memory context) external view returns (bool applicable);
}
