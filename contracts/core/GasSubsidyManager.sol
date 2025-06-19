// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccessControlCenter.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../errors/Errors.sol";

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
    event GasRefunded(bytes32 moduleId, address relayer, uint256 refund);
    event GasTankFunded(address indexed from, uint256 value, uint256 newBalance);

    /// Установить лимит возврата газа на одну транзакцию для модуля
    function setGasRefundLimit(bytes32 moduleId, uint256 limit) external onlyAdmin {
        gasRefundPerTx[moduleId] = limit;
        emit GasRefundLimitSet(moduleId, limit);
    }

    modifier onlyAdmin() {
        if (!access.hasRole(access.DEFAULT_ADMIN_ROLE(), msg.sender)) revert NotAdmin();
        _;
    }

    modifier onlyFeatureOwner() {
        if (!access.hasRole(access.FEATURE_OWNER_ROLE(), msg.sender)) revert NotFeatureOwner();
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

    modifier onlyAutomation() {
        if (!access.hasRole(access.AUTOMATION_ROLE(), msg.sender)) revert NotAutomation();
        _;
    }

    /// @notice Refund gas to relayer with per-transaction limit check
    function refundGas(
        bytes32 moduleId,
        address payable relayer,
        uint256 gasUsed,
        uint256 priorityCap
    ) external onlyAutomation {
        uint256 price =
            tx.gasprice < block.basefee + priorityCap
                ? tx.gasprice
                : block.basefee + priorityCap;
        if (price == 0) revert PriceZero();
        uint256 limit = gasRefundPerTx[moduleId];
        if (limit == 0) revert RefundDisabled();
        if (gasUsed == 0) revert GasZero();
        if (gasUsed > limit / price) revert ExceedsRefundLimit();
        uint256 refund = price * gasUsed;
        if (address(this).balance < refund) revert InsufficientBalance();
        relayer.transfer(refund);
        emit GasRefunded(moduleId, relayer, refund);
    }

    receive() external payable {
        emit GasTankFunded(msg.sender, msg.value, address(this).balance);
    }

    function setAccessControl(address newAccess) external onlyAdmin {
        access = AccessControlCenter(newAccess);
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyAdmin {
        if (newImplementation == address(0)) revert InvalidImplementation();
    }

    uint256[50] private __gap;
}
