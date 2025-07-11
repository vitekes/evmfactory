// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './IPaymentComponent.sol';
import './IPaymentProcessor.sol';

/// @title IProcessorRegistry
/// @notice Интерфейс реестра обработчиков платежей
/// @dev Управляет регистрацией и последовательностью обработчиков
interface IProcessorRegistry is IPaymentComponent {
    /// @notice Зарегистрировать новый процессор
    /// @param processor Адрес процессора
    /// @param position Позиция в цепочке (0 - в конец)
    /// @return success Успешность операции
    function registerProcessor(address processor, uint256 position) external returns (bool success);

    /// @notice Удалить процессор из реестра
    /// @param processorName Имя процессора
    /// @return success Успешность операции
    function removeProcessor(string calldata processorName) external returns (bool success);

    /// @notice Получить адрес процессора по имени
    /// @param name Имя процессора
    /// @return processorAddress Адрес процессора
    function getProcessorByName(string calldata name) external view returns (address processorAddress);

    /// @notice Получить цепочку процессоров для модуля
    /// @param moduleId Идентификатор модуля
    /// @return processors Массив адресов процессоров
    function getProcessorChain(bytes32 moduleId) external view returns (address[] memory processors);

    /// @notice Обновить порядок процессоров для модуля
    /// @param moduleId Идентификатор модуля
    /// @param newOrder Новый порядок процессоров (массив имен)
    /// @return success Успешность операции
    function updateProcessorOrder(bytes32 moduleId, string[] calldata newOrder) external returns (bool success);

    /// @notice Включить/выключить процессор для модуля
    /// @param moduleId Идентификатор модуля
    /// @param processorName Имя процессора
    /// @param enabled Включен/выключен
    /// @return success Успешность операции
    function setProcessorEnabled(
        bytes32 moduleId,
        string calldata processorName,
        bool enabled
    ) external returns (bool success);

    /// @notice Проверить, включен ли процессор для модуля
    /// @param moduleId Идентификатор модуля
    /// @param processorName Имя процессора
    /// @return enabled Статус процессора
    function isProcessorEnabled(bytes32 moduleId, string calldata processorName) external view returns (bool enabled);
}
