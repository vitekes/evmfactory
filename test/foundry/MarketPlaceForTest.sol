// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * MarketplaceForTest.sol
 * ---------------------
 * Тестовый wrapper для контракта Marketplace.
 * Основная цель — дать тестовому контракту (msg.sender) роль DEFAULT_ADMIN_ROLE
 * без изменения продакшн-кода.
 */

import {Marketplace} from "contracts/modules/marketplace/Marketplace.sol";

/// @title MarketplaceForTest
/// @dev Wrapper над Marketplace, назначающий deployer'у DEFAULT_ADMIN_ROLE
contract MarketplaceForTest is Marketplace {
    /**
     * @param registry Адрес Registry, передаётся в базовый конструктор
     * @param gateway Адрес Gateway, передаётся в базовый конструктор
     * @param moduleId Идентификатор модуля, передаётся в базовый конструктор
     */
    constructor(
        address registry,
        address gateway,
        bytes32 moduleId
    ) Marketplace(registry, gateway, moduleId) {
        // Вызов базового конструктора Marketplace
        // Затем сразу назначаем тестовому контракту DEFAULT_ADMIN_ROLE
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
}
