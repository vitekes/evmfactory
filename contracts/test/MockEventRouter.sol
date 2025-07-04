// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../interfaces/IEventRouter.sol';

/// @title MockEventRouter
/// @notice Простая реализация EventRouter для тестирования
/// @dev Используется в тестах для эмуляции EventRouter
contract MockEventRouter is IEventRouter {
    event EventRouted(EventKind indexed kind, bytes data);

    /// @notice Маршрутизация события
    /// @param kind Тип события
    /// @param data Данные события
    function route(EventKind kind, bytes calldata data) external override {
        emit EventRouted(kind, data);
    }
}
