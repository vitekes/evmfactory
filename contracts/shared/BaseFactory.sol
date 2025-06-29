// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../interfaces/core/IRegistry.sol';
import '../core/AccessControlCenter.sol';
import '../errors/Errors.sol';
import './CloneFactory.sol';
import '../interfaces/CoreDefs.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

abstract contract BaseFactory is CloneFactory, ReentrancyGuard {
    IRegistry public immutable registry;
    bytes32 public immutable MODULE_ID;

    bytes32 public constant FACTORY_ADMIN = keccak256('FACTORY_ADMIN');

    constructor(address _registry, address paymentGateway, bytes32 moduleId) {
        registry = IRegistry(_registry);
        MODULE_ID = moduleId;

        // Проверяем, что модуль зарегистрирован в реестре
        // Если нет, то сервисы будут привязаны позже вне конструктора
        try IRegistry(_registry).getFeature(moduleId) returns (address, uint8) {
            // Если модуль зарегистрирован, регистрируем платежный шлюз
            try IRegistry(_registry).setModuleServiceAlias(
                moduleId, 
                "PaymentGateway",
                paymentGateway
            ) {} catch {}
        } catch {}
    }

    // Константа для идентификатора сервиса ACL
    bytes32 private constant ACL_SERVICE = keccak256('AccessControlCenter');

    modifier onlyFactoryAdmin() {
        AccessControlCenter acl = AccessControlCenter(registry.getCoreService(ACL_SERVICE));
        if (!acl.hasRole(FACTORY_ADMIN, msg.sender)) revert NotFactoryAdmin();
        _;
    }
}
