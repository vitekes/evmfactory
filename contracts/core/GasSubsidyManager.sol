// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccessControlCenter.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract GasSubsidyManager is Initializable, UUPSUpgradeable {
    AccessControlCenter public access;

    // moduleId => user => имеет ли право на покрытие газа
    mapping(bytes32 => mapping(address => bool)) public isEligible;

    // moduleId => адрес контракта => включено ли покрытие газа
    mapping(bytes32 => mapping(address => bool)) public gasCoverageEnabled;

    event GasRefundLimitSet(bytes32 moduleId, uint256 limit);
    // moduleId => максимальный возврат газа за транзакцию
    mapping(bytes32 => uint256) public gasRefundPerTx;

    event EligibilitySet(bytes32 moduleId, address user, bool allowed);
    event GasCoverageEnabled(bytes32 moduleId, address contractAddress, bool enabled);

    /// Установить лимит возврата газа на одну транзакцию для модуля
    function setGasRefundLimit(bytes32 moduleId, uint256 limit) external onlyAdmin {
        gasRefundPerTx[moduleId] = limit;
        emit GasRefundLimitSet(moduleId, limit);
    }

    modifier onlyAdmin() {
        require(access.hasRole(access.DEFAULT_ADMIN_ROLE(), msg.sender), "not admin");
        _;
    }

    modifier onlyFeatureOwner() {
        require(access.hasRole(access.FEATURE_OWNER_ROLE(), msg.sender), "not feature owner");
        _;
    }

    function initialize(address accessControl) public initializer {
        __UUPSUpgradeable_init();
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

    /// @notice Refund gas to relayer with per-transaction limit check
    function refundGas(bytes32 moduleId, address payable relayer, uint256 gasUsed) external onlyAdmin {
        uint256 price = tx.gasprice;
        require(gasUsed <= gasRefundPerTx[moduleId] / price, "Exceeds refund limit");
        uint256 refund = price * gasUsed;
        require(address(this).balance >= refund, "Insufficient balance");
        relayer.transfer(refund);
    }

    receive() external payable {}

    function setAccessControl(address newAccess) external onlyAdmin {
        access = AccessControlCenter(newAccess);
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyAdmin {
        require(newImplementation != address(0), "invalid implementation");
    }

    uint256[50] private __gap;
}
