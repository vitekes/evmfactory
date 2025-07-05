// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../interfaces/ICoreKernel.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '../errors/Errors.sol';
import '../interfaces/IEventRouter.sol';

/// @title EventRouter
/// @notice Централизованный маршрутизатор событий для межмодульного взаимодействия
/// @dev Позволяет модулям генерировать типизированные события, которые могут отслеживаться внешними системами
contract EventRouter is Initializable, UUPSUpgradeable, IEventRouter {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    ICoreKernel public access;

    /// @notice Структура для хранения маршрутизированного события
    struct RoutedEvent {
        EventKind kind;
        bytes payload;
    }

    /// @notice Событие генерируется при каждой маршрутизации
    /// @param kind Тип события
    /// @param payload Данные события в формате bytes
    event EventRouted(EventKind indexed kind, bytes payload);

    /// @notice Initialize the event router
    /// @param accessControl Address of CoreKernel
    function initialize(address accessControl) public initializer {
        __UUPSUpgradeable_init();
        if (accessControl == address(0)) revert ZeroAddress();
        access = ICoreKernel(accessControl);
    }

    /// @notice Route an event from a module
    /// @param kind Type of event
    /// @param payload Event data
    function route(EventKind kind, bytes calldata payload) external override {
        // Проверяем, что отправитель имеет роль MODULE_ROLE
        if (!access.hasRole(access.MODULE_ROLE(), msg.sender)) revert NotModule();
        // Не принимаем неизвестные типы событий
        if (kind == EventKind.Unknown) revert InvalidEventKind();
        // Эмитируем событие
        emit EventRouted(kind, payload);
    }

    /// @notice Authorize implementation upgrade - restricted to admin
    /// @param newImplementation Address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal view override {
        if (!access.hasRole(access.DEFAULT_ADMIN_ROLE(), msg.sender)) revert NotAdmin();
        if (newImplementation == address(0)) revert InvalidImplementation();
    }

    uint256[50] private __gap;
}
