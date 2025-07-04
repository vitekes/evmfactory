// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../interfaces/IEventRouter.sol';

/// @title MockEventRouter
/// @notice Тестовый маршрутизатор событий для модульного тестирования
/// @dev Используется только для тестирования, не применять в продакшене
contract MockEventRouter is IEventRouter {
    // События для отслеживания вызовов в тестах
    event EventRouted(EventKind indexed kind, bytes data);

    /// @notice Маршрутизирует событие
    /// @param kind Тип события
    /// @param data Данные события
    function route(EventKind kind, bytes calldata data) external {
        emit EventRouted(kind, data);
    }
}
