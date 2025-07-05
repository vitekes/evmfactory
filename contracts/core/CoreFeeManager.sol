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
import '../interfaces/CoreDefs.sol';
import '../interfaces/IRegistry.sol';
import '../lib/Native.sol';

contract CoreFeeManager is Initializable, ReentrancyGuardUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    using Address for address payable;
    using SafeERC20 for IERC20;
    using Native for address;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Maximum fee in basis points (10000 = 100%)
    uint256 public constant MAX_FEE_BPS = 1000; // 10%

    AccessControlCenter public access;
    IRegistry public registry;

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
    /// @param registryAddress Address of Registry
    function initialize(address accessControl, address registryAddress) public initializer {
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        if (accessControl == address(0)) revert ZeroAddress();
        access = AccessControlCenter(accessControl);

        if (registryAddress != address(0)) {
            registry = IRegistry(registryAddress);
        }
    }

    /// @notice Calculate and collect fee
    /// @param moduleId Module identifier
    /// @param token Fee token
    /// @param amount Payment amount
    /// @return feeAmount Actual fee charged
    function collect(
        bytes32 moduleId,
        address token,
        uint256 amount
    ) external onlyFeatureOwner nonReentrant whenNotPaused returns (uint256 feeAmount) {
        address payer = msg.sender;

        // Use unified fee calculation logic
        feeAmount = _calculateFeeInternal(moduleId, token, amount, payer);

        // If fee is zero, return early
        if (feeAmount == 0) return 0;
        if (feeAmount >= amount) revert FeeExceedsAmount();

        IERC20(token).safeTransferFrom(payer, address(this), feeAmount);
        collectedFees[moduleId][token] += feeAmount;

        // Emit fee collection event
        _emitFeeCollectedEvent(moduleId, token, feeAmount);
    }

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

        // Emit fee deposit event
        _emitFeeCollectedEvent(moduleId, token, amount);
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

        // Emit fee withdrawal event
        _emitFeeWithdrawnEvent(moduleId, token, to, amount);
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

    /// @notice Calculate fee for any payment (native or token)
    /// @param moduleId Module identifier
    /// @param token Token address (0x0 or ETH_SENTINEL for native currency)
    /// @param amount Payment amount
    /// @return feeAmount Calculated fee amount
    function calculateFee(bytes32 moduleId, address token, uint256 amount) external view returns (uint256) {
        return _calculateFeeInternal(moduleId, token, amount, msg.sender);
    }

    /// @notice Calculate fee for native currency payments (backwards compatibility)
    /// @param moduleId Module identifier
    /// @param amount Payment amount
    /// @return feeAmount Calculated fee amount
    function calculateFee(bytes32 moduleId, uint256 amount) external view returns (uint256) {
        return _calculateFeeInternal(moduleId, Native.ETH_SENTINEL, amount, msg.sender);
    }

    /// @dev Internal function to calculate fee amount based on fixed and percentage fees
    /// @param moduleId Module identifier
    /// @param token Token address (ETH_SENTINEL for native)
    /// @param amount Gross payment amount
    /// @param payer Address of the payer
    /// @return feeAmount Total fee amount
    function _calculateFeeInternal(
        bytes32 moduleId,
        address token,
        uint256 amount,
        address payer
    ) internal view returns (uint256) {
        // Early exit for zero cases
        if (isZeroFeeAddress[moduleId][payer] || amount == 0) return 0;

        // Normalize token address for native currency
        address normalizedToken = token.isNative() ? Native.ETH_SENTINEL : token;

        // Get fee settings
        uint16 pFee = percentFee[moduleId][normalizedToken];
        uint256 feeAmount = fixedFee[moduleId][normalizedToken];

        // Add percentage fee if set
        if (pFee > 0) {
            if (pFee > 10_000) revert FeeTooHigh();
            feeAmount += (amount * pFee) / 10_000;
        }

        // Check fee size limits
        if (feeAmount >= amount) return 0;

        // Apply MAX_FEE_BPS limit
        uint256 maxFee = (amount * MAX_FEE_BPS) / 10000;
        return feeAmount > maxFee ? maxFee : feeAmount;
    }

    /// @notice Replace the AccessControlCenter contract
    /// @param newAccess Address of the new AccessControlCenter
    function setAccessControl(address newAccess) external onlyAdmin {
        if (newAccess == address(0)) revert InvalidAddress();
        access = AccessControlCenter(newAccess);
    }

    /// @notice Set the registry contract address
    /// @param newRegistry Address of the new Registry
    function setRegistry(address newRegistry) external onlyAdmin {
        if (newRegistry == address(0)) revert InvalidAddress();
        registry = IRegistry(newRegistry);
    }

    /// @notice Pause fee collection
    function pause() external onlyAdmin {
        _pause();
    }

    /// @notice Unpause fee collection
    function unpause() external onlyAdmin {
        _unpause();
    }

    /// @dev Emit fee collection event
    /// @param moduleId Module identifier
    /// @param token Token address
    /// @param amount Fee amount
    function _emitFeeCollectedEvent(bytes32 moduleId, address token, uint256 amount) internal {
        emit FeeCollected(moduleId, token, amount);
    }

    /// @dev Emit fee withdrawal event
    /// @param moduleId Module identifier
    /// @param token Token address
    /// @param to Recipient address
    /// @param amount Fee amount
    function _emitFeeWithdrawnEvent(bytes32 moduleId, address token, address to, uint256 amount) internal {
        emit FeeWithdrawn(moduleId, token, to, amount);
    }

    /// @notice Authorize implementation upgrade - restricted to admin
    /// @param newImplementation Address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal view override onlyAdmin {
        if (newImplementation == address(0)) revert InvalidImplementation();
    }

    uint256[50] private __gap;
}
