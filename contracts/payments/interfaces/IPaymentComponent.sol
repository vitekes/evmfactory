// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IPaymentComponent
/// @notice Базовый интерфейс для всех компонентов платежной системы
/// @dev Определяет общие методы для идентификации компонентов
interface IPaymentComponent {
    /// @notice Получить имя компонента
    /// @return name Имя компонента
    function getName() external pure returns (string memory name);

    /// @notice Получить версию компонента
    /// @return version Версия компонента
    function getVersion() external pure returns (string memory version);
}
