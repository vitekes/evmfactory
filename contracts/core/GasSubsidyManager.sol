// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./AccessControlCenter.sol";

contract GasSubsidyManager {
    AccessControlCenter public access;

    // moduleId => user => имеет ли право на покрытие газа
    mapping(bytes32 => mapping(address => bool)) public isEligible;

    // moduleId => адрес контракта => включено ли покрытие газа
    mapping(bytes32 => mapping(address => bool)) public gasCoverageEnabled;

    event EligibilitySet(bytes32 moduleId, address user, bool allowed);
    event GasCoverageEnabled(bytes32 moduleId, address contractAddress, bool enabled);

    modifier onlyAdmin() {
        require(access.hasRole(access.DEFAULT_ADMIN_ROLE(), msg.sender), "not admin");
        _;
    }

    modifier onlyFeatureOwner() {
        require(access.hasRole(access.FEATURE_OWNER_ROLE(), msg.sender), "not feature owner");
        _;
    }

    constructor(address accessControl) {
        access = AccessControlCenter(accessControl);
    }

    /// Пользователь получает право не платить за газ (его покроет система)
    function setEligibility(bytes32 moduleId, address user, bool status) external onlyFeatureOwner {
        isEligible[moduleId][user] = status;
        emit EligibilitySet(moduleId, user, status);
    }

    /// Модуль (feature) регистрирует себя для поддержки покрытия газа
    function setGasCoverageEnabled(bytes32 moduleId, address contractAddress, bool enabled) external onlyFeatureOwner {
        gasCoverageEnabled[moduleId][contractAddress] = enabled;
        emit GasCoverageEnabled(moduleId, contractAddress, enabled);
    }

    /// Проверка перед выполнением действия (можно вызывать в модуле)
    function isGasFree(bytes32 moduleId, address user, address contractAddress) external view returns (bool) {
        return gasCoverageEnabled[moduleId][contractAddress] && isEligible[moduleId][user];
    }

    function setAccessControl(address newAccess) external onlyAdmin {
        access = AccessControlCenter(newAccess);
    }
}
