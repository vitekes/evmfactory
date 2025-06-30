// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './AccessControlCenter.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '../errors/Errors.sol';

contract GasSubsidyManager is Initializable, UUPSUpgradeable {
    using Address for address payable;
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    AccessControlCenter public access;

    // moduleId => user => whether gas coverage is allowed
    mapping(bytes32 => mapping(address => bool)) public isEligible;

    // moduleId => contract address => gas coverage enabled
    mapping(bytes32 => mapping(address => bool)) public gasCoverageEnabled;

    event GasRefundLimitSet(bytes32 moduleId, uint256 limit);
    // moduleId => max gas refund per transaction
    mapping(bytes32 => uint256) public gasRefundPerTx;

    event EligibilitySet(bytes32 moduleId, address user, bool allowed);
    event GasCoverageEnabled(bytes32 moduleId, address contractAddress, bool enabled);
    event GasRefunded(bytes32 moduleId, address relayer, uint256 refund);
    event GasTankFunded(address indexed from, uint256 value, uint256 newBalance);

    /// @notice Set per-transaction gas refund limit for a module
    /// @param moduleId Module identifier
    /// @param limit Maximum refund amount
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

    /// @notice Grant gas payment exemption to a user
    /// @param moduleId Module identifier
    /// @param user Address receiving the privilege
    /// @param status Eligibility flag
    function setEligibility(bytes32 moduleId, address user, bool status) external onlyFeatureOwner {
        isEligible[moduleId][user] = status;
        emit EligibilitySet(moduleId, user, status);
    }

    /// @notice Enable gas coverage for a contract
    /// @param moduleId Module identifier
    /// @param contractAddress Contract address to enable coverage for
    /// @param enabled Whether coverage is enabled
    function setGasCoverageEnabled(bytes32 moduleId, address contractAddress, bool enabled) external onlyFeatureOwner {
        gasCoverageEnabled[moduleId][contractAddress] = enabled;
        emit GasCoverageEnabled(moduleId, contractAddress, enabled);
    }

    /// @notice Check whether gas is subsidized for a call
    /// @param moduleId Module identifier
    /// @param user User address
    /// @param contractAddress Contract being called
    /// @return True if the user is eligible and coverage is enabled
    function isGasFree(bytes32 moduleId, address user, address contractAddress) external view returns (bool) {
        return gasCoverageEnabled[moduleId][contractAddress] && isEligible[moduleId][user];
    }

    modifier onlyAutomation() {
        if (!access.hasRole(access.AUTOMATION_ROLE(), msg.sender)) revert NotAutomation();
        _;
    }

    /// @notice Refund execution gas to the relayer.
    /// @dev Checks the per-transaction refund limit set via {setGasRefundLimit}.
    ///      Reverts with {RefundDisabled} if refunds are disabled, {GasZero} if
    ///      `gasUsed` is zero, {ExceedsRefundLimit} if the refund exceeds the
    ///      module limit, or {InsufficientBalance} when funds are insufficient.
    /// @param moduleId Identifier of the module requesting the refund.
    /// @param relayer Address that paid for the transaction gas.
    /// @param gasUsed Amount of gas to refund.
    /// @param priorityCap Priority fee cap used to calculate the gas price.
    function refundGas(
        bytes32 moduleId,
        address payable relayer,
        uint256 gasUsed,
        uint256 priorityCap
    ) external onlyAutomation {
        uint256 price = tx.gasprice < block.basefee + priorityCap ? tx.gasprice : block.basefee + priorityCap;
        if (price == 0) revert PriceZero();
        uint256 limit = gasRefundPerTx[moduleId];
        if (limit == 0) revert RefundDisabled();
        if (gasUsed == 0) revert GasZero();
        if (gasUsed > limit / price) revert ExceedsRefundLimit();
        uint256 refund = price * gasUsed;
        if (address(this).balance < refund) revert InsufficientBalance();
        relayer.sendValue(refund);
        emit GasRefunded(moduleId, relayer, refund);
    }

    receive() external payable {
        emit GasTankFunded(msg.sender, msg.value, address(this).balance);
    }

    function setAccessControl(address newAccess) external onlyAdmin {
        if (newAccess == address(0)) revert InvalidAddress();
        access = AccessControlCenter(newAccess);
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyAdmin {
        if (newImplementation == address(0)) revert InvalidImplementation();
    }

    uint256[50] private __gap;
}
