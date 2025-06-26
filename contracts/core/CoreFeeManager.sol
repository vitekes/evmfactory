// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './AccessControlCenter.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '../errors/Errors.sol';

contract CoreFeeManager is Initializable, ReentrancyGuardUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    using Address for address payable;
    using SafeERC20 for IERC20;

    AccessControlCenter public access;

    /// @notice moduleId => token => fee % (in basis points: 100 = 1%)
    mapping(bytes32 => mapping(address => uint16)) public percentFee;

    /// @notice moduleId => token => fixed fee (in tokens)
    mapping(bytes32 => mapping(address => uint256)) public fixedFee;

    /// @notice moduleId => token => collected amount
    mapping(bytes32 => mapping(address => uint256)) public collectedFees;

    /// @notice moduleId => address => fee exempt
    mapping(bytes32 => mapping(address => bool)) public isZeroFeeAddress;

    event FeeCollected(bytes32 indexed moduleId, address indexed token, uint256 amount);
    event FeeWithdrawn(bytes32 indexed moduleId, address indexed token, address to, uint256 amount);
    event GasTankFunded(address indexed from, uint256 value, uint256 newBalance);

    modifier onlyFeatureOwner() {
        if (!access.hasRole(access.FEATURE_OWNER_ROLE(), msg.sender)) revert NotFeatureOwner();
        _;
    }

    modifier onlyAdmin() {
        if (!access.hasRole(access.DEFAULT_ADMIN_ROLE(), msg.sender)) revert NotAdmin();
        _;
    }

    /// @notice Initialize the fee manager
    /// @param accessControl Address of AccessControlCenter
    function initialize(address accessControl) public initializer {
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        access = AccessControlCenter(accessControl);
    }

    /// @notice Calculate and collect fee
    /// @param moduleId Module identifier
    /// @param token Fee token
    /// @param payer Address paying the fee
    /// @param amount Payment amount
    /// @return feeAmount Actual fee charged
    function collect(
        bytes32 moduleId,
        address token,
        address payer,
        uint256 amount
    ) external onlyFeatureOwner nonReentrant whenNotPaused returns (uint256 feeAmount) {
        if (isZeroFeeAddress[moduleId][payer]) return 0;

        uint16 pFee = percentFee[moduleId][token];
        uint256 fFee = fixedFee[moduleId][token];

        if (pFee > 10_000) revert FeeTooHigh();
        feeAmount = fFee + ((amount * pFee) / 10_000);
        if (feeAmount >= amount) revert FeeExceedsAmount();
        if (feeAmount > 0) {
            IERC20(token).safeTransferFrom(payer, address(this), feeAmount);

            collectedFees[moduleId][token] += feeAmount;
            emit FeeCollected(moduleId, token, feeAmount);
        }
    }

    /// @notice Deposit a specific amount of fees for a module without calculation
    /// @notice Deposit a specific amount of fees for a module without calculation
    /// @param moduleId Module identifier
    /// @param token Fee token
    /// @param amount Amount to deposit
    function depositFee(
        bytes32 moduleId,
        address token,
        uint256 amount
    ) external onlyFeatureOwner nonReentrant whenNotPaused {
        if (amount == 0) revert AmountZero();
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        collectedFees[moduleId][token] += amount;
        emit FeeCollected(moduleId, token, amount);
    }

    /// @notice Withdraw collected fees for a module
    /// @param moduleId Module identifier
    /// @param token Fee token
    /// @param to Recipient address
    function withdrawFees(bytes32 moduleId, address token, address to) external onlyAdmin nonReentrant whenNotPaused {
        uint256 amount = collectedFees[moduleId][token];
        if (amount == 0) revert NothingToWithdraw();

        collectedFees[moduleId][token] = 0;
        IERC20(token).safeTransfer(to, amount);

        emit FeeWithdrawn(moduleId, token, to, amount);
        emit GasTankFunded(to, amount, IERC20(token).balanceOf(to));
    }

    /// @notice Set percentage fee
    /// @param moduleId Module identifier
    /// @param token Fee token
    /// @param feeBps Fee in basis points
    function setPercentFee(bytes32 moduleId, address token, uint16 feeBps) external onlyFeatureOwner {
        if (feeBps > 10_000) revert FeeTooHigh();
        percentFee[moduleId][token] = feeBps;
    }

    /// @notice Set fixed fee
    /// @param moduleId Module identifier
    /// @param token Fee token
    /// @param feeAmount Fixed amount of fee tokens
    function setFixedFee(bytes32 moduleId, address token, uint256 feeAmount) external onlyFeatureOwner {
        fixedFee[moduleId][token] = feeAmount;
    }

    /// @notice Mark address as zero-fee
    /// @param moduleId Module identifier
    /// @param user Address to mark
    /// @param status Whether zero-fee is enabled
    function setZeroFeeAddress(bytes32 moduleId, address user, bool status) external onlyFeatureOwner {
        isZeroFeeAddress[moduleId][user] = status;
    }

    /// @notice Replace the AccessControlCenter contract
    /// @param newAccess Address of the new AccessControlCenter
    function setAccessControl(address newAccess) external onlyAdmin {
        access = AccessControlCenter(newAccess);
    }

    /// @notice Pause fee collection
    function pause() external onlyAdmin {
        _pause();
    }

    /// @notice Unpause fee collection
    function unpause() external onlyAdmin {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyAdmin {
        if (newImplementation == address(0)) revert InvalidImplementation();
    }

    uint256[50] private __gap;
}
