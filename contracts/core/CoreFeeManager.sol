// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './CoreKernel.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '../errors/Errors.sol';
import '../interfaces/CoreDefs.sol';
import '../interfaces/IEventRouter.sol';
import '../interfaces/ICoreKernel.sol';
import '../utils/Native.sol';

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

    ICoreKernel public core;

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
        if (!core.hasRole(core.FEATURE_OWNER_ROLE(), msg.sender)) revert NotFeatureOwner();
        _;
    }

    modifier onlyAdmin() {
        if (!core.hasRole(core.DEFAULT_ADMIN_ROLE(), msg.sender)) revert NotAdmin();
        _;
    }

    /// @notice Initialize the fee manager
    /// @param accessControl Address of the CoreKernel contract
    /// @param registryAddress Unused legacy parameter
    function initialize(address accessControl, address registryAddress) public initializer {
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        if (accessControl == address(0)) revert ZeroAddress();
        core = ICoreKernel(accessControl);
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

    /// @notice Replace the CoreKernel contract
    /// @param newAccess Address of the new CoreKernel
    function setAccessControl(address newAccess) external onlyAdmin {
        if (newAccess == address(0)) revert InvalidAddress();
        core = ICoreKernel(newAccess);
    }

    /// @notice Pause fee collection
    function pause() external onlyAdmin {
        _pause();
    }

    /// @notice Unpause fee collection
    function unpause() external onlyAdmin {
        _unpause();
    }

    /// @dev Get event router for a module
    /// @param moduleId Module identifier
    /// @return router Event router address or address(0) if not available
    function _getEventRouter(bytes32 moduleId) internal view returns (address router) {
        router = core.getModuleService(moduleId, CoreDefs.SERVICE_EVENT_ROUTER);
    }

    /// @dev Emit fee collection event
    /// @param moduleId Module identifier
    /// @param token Token address
    /// @param amount Fee amount
    function _emitFeeCollectedEvent(bytes32 moduleId, address token, uint256 amount) internal {
        address router = _getEventRouter(moduleId);
        if (router != address(0)) {
            IEventRouter(router).route(
                IEventRouter.EventKind.FeeCollected,
                abi.encode(moduleId, token, amount, uint16(1))
            );
        } else {
            emit FeeCollected(moduleId, token, amount);
        }
    }

    /// @dev Emit fee withdrawal event
    /// @param moduleId Module identifier
    /// @param token Token address
    /// @param to Recipient address
    /// @param amount Fee amount
    function _emitFeeWithdrawnEvent(bytes32 moduleId, address token, address to, uint256 amount) internal {
        address router = _getEventRouter(moduleId);
        if (router != address(0)) {
            IEventRouter(router).route(
                IEventRouter.EventKind.FeeWithdrawn,
                abi.encode(moduleId, token, to, amount, uint16(1))
            );
        } else {
            emit FeeWithdrawn(moduleId, token, to, amount);
        }
    }

    /// @notice Authorize implementation upgrade - restricted to admin
    /// @param newImplementation Address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal view override onlyAdmin {
        if (newImplementation == address(0)) revert InvalidImplementation();
    }

    uint256[50] private __gap;
}
