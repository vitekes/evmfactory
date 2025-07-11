// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './IPaymentComponent.sol';

/// @title IPaymentFactory
/// @notice Обобщенный интерфейс для фабрик в платежной системе
/// @dev Определяет базовые методы для создания компонентов
interface IPaymentFactory is IPaymentComponent {
    /// @notice Создать компонент с указанными параметрами
    /// @param id Идентификатор компонента (например, moduleId)
    /// @param config Конфигурация в формате байтов
    /// @return component Адрес созданного компонента
    function createComponent(bytes32 id, bytes calldata config) external returns (address component);

    /// @notice Получить созданный компонент по идентификатору
    /// @param id Идентификатор компонента
    /// @return component Адрес компонента
    function getComponent(bytes32 id) external view returns (address component);
}
