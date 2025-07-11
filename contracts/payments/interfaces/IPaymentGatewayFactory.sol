// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './IPaymentComponent.sol';
import './IGateway.sol';

/// @title IPaymentGatewayFactory
/// @notice Интерфейс для фабрики платежных шлюзов
/// @dev Создает и настраивает экземпляры шлюзов для модулей
interface IPaymentGatewayFactory is IPaymentComponent {
    /// @notice Настройки платежного шлюза
    struct GatewayConfig {
        address[] defaultProcessors; // Процессоры по умолчанию
        uint16 gatewayFeePercentage; // Базовая комиссия шлюза (в базисных пунктах)
        address gatewayFeeRecipient; // Получатель комиссий
        address fallbackProcessor; // Процессор для аварийных ситуаций
        bool pausable; // Можно ли приостанавливать шлюз
    }

    /// @notice Создать экземпляр платежного шлюза для модуля
    /// @param moduleId Идентификатор модуля
    /// @param config Начальная конфигурация шлюза
    /// @return gateway Адрес созданного шлюза
    function createGateway(bytes32 moduleId, GatewayConfig calldata config) external returns (address gateway);

    /// @notice Получить экземпляр шлюза для модуля
    /// @param moduleId Идентификатор модуля
    /// @return gateway Адрес шлюза
    function getGateway(bytes32 moduleId) external view returns (address gateway);

    /// @notice Обновить конфигурацию шлюза для модуля
    /// @param moduleId Идентификатор модуля
    /// @param config Новая конфигурация
    /// @return success Успешность операции
    function updateGatewayConfig(bytes32 moduleId, GatewayConfig calldata config) external returns (bool success);

    /// @notice Получить конфигурацию шлюза для модуля
    /// @param moduleId Идентификатор модуля
    /// @return config Конфигурация шлюза
    function getGatewayConfig(bytes32 moduleId) external view returns (GatewayConfig memory config);

    /// @notice Получить реестр процессоров
    /// @return registry Адрес реестра процессоров
    function getProcessorRegistry() external view returns (address registry);
}
