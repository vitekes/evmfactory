// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './AccessControlCenter.sol';
import "../interfaces/IRegistry.sol";
import "../interfaces/IMultiValidator.sol";
import '../interfaces/IPriceOracle.sol';
import '../interfaces/IGateway.sol';
import './CoreFeeManager.sol';
import '../errors/Errors.sol';
import '../lib/SignatureLib.sol';
import '../interfaces/CoreDefs.sol';
import "../interfaces/IEventRouter.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '../utils/Native.sol';

abstract contract PaymentGateway is Initializable, ReentrancyGuardUpgradeable, PausableUpgradeable, UUPSUpgradeable, IGateway {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    using Address for address payable;
    using SafeERC20 for IERC20;
    using Native for address;

    /// @dev Maximum fee in basis points (10000 = 100%)
    uint256 public constant MAX_FEE_BPS = 1000; // 10%

    AccessControlCenter public access;
    IRegistry public registry;
    CoreFeeManager public feeManager;

    // Per-module nonces to prevent signature reuse across modules
    mapping(address => mapping(bytes32 => uint256)) public nonces;

    // Domain separator for EIP-712 signatures
    bytes32 public DOMAIN_SEPARATOR;

    event PaymentProcessed(
        address indexed payer,
        address indexed token,
        uint256 grossAmount,
        uint256 fee,
        uint256 netAmount,
        bytes32 moduleId,
        uint16 version
    );

    event PriceConverted(
        address indexed baseToken,
        address indexed paymentToken,
        uint256 baseAmount,
        uint256 paymentAmount,
        bytes32 moduleId,
        uint16 version
    );

    event DomainSeparatorUpdated(
        bytes32 oldDomainSeparator,
        bytes32 newDomainSeparator,
        uint256 chainId
    );

    modifier onlyFeatureOwner() {
        if (!access.hasRole(access.FEATURE_OWNER_ROLE(), msg.sender)) revert NotFeatureOwner();
        _;
    }

    modifier onlyAdmin() {
        if (!access.hasRole(access.DEFAULT_ADMIN_ROLE(), msg.sender)) revert NotAdmin();
        _;
    }

    function initialize(address accessControl, address registry_, address feeManager_) public initializer {
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        if (accessControl == address(0)) revert ZeroAddress();
        if (registry_ == address(0)) revert ZeroAddress();
        if (feeManager_ == address(0)) revert ZeroAddress();

        access = AccessControlCenter(accessControl);
        registry = IRegistry(registry_);
        feeManager = CoreFeeManager(feeManager_);

        _updateDomainSeparator();
    }

    /// @notice Updates domain separator if chain ID changes
    /// @dev Called during initialization and can be called manually after chain forks
    function updateDomainSeparator() external onlyAdmin {
        _updateDomainSeparator();
    }

    /// @dev Internal function to update domain separator
    function _updateDomainSeparator() internal {
        bytes32 oldDomainSeparator = DOMAIN_SEPARATOR;
        bytes32 newDomainSeparator = keccak256(
            abi.encode(
                keccak256('EIP712Domain(uint256 chainId,address verifyingContract)'),
                block.chainid,
                address(this)
            )
        );

        DOMAIN_SEPARATOR = newDomainSeparator;

        emit DomainSeparatorUpdated(oldDomainSeparator, newDomainSeparator, block.chainid);
    }

    // getPriceInPreferredCurrency was removed as redundant - use getPriceInCurrency directly

    /// @notice Converts amount from one token to another (alias for getPriceInCurrency for interface compatibility)
    /// @param moduleId Module ID
    /// @param baseToken Base token (0x0 or ETH_SENTINEL for native currency)
    /// @param paymentToken Payment token (0x0 or ETH_SENTINEL for native currency)
    /// @param baseAmount Amount in base token
    /// @return paymentAmount Amount in payment token
    function convertAmount(
        bytes32 moduleId,
        address baseToken,
        address paymentToken,
        uint256 baseAmount
    ) external view returns (uint256 paymentAmount) {
        return getPriceInCurrency(moduleId, baseToken, paymentToken, baseAmount);
    }

    /// @notice Gets the price in specified currency with detailed validation
    /// @param moduleId Module ID
    /// @param baseToken Base token (0x0 or ETH_SENTINEL for native currency)
    /// @param paymentToken Payment token (0x0 or ETH_SENTINEL for native currency)
    /// @param baseAmount Amount in base token
    /// @return paymentAmount Amount in payment token
    function getPriceInCurrency(
        bytes32 moduleId,
        address baseToken,
        address paymentToken,
        uint256 baseAmount
    ) public view returns (uint256 paymentAmount) {
        if (baseAmount == 0) return 0;

        // Normalize native currency addresses to ETH_SENTINEL for consistency
        address normalizedBase = baseToken.isNative() ? Native.ETH_SENTINEL : baseToken;
        address normalizedPayment = paymentToken.isNative() ? Native.ETH_SENTINEL : paymentToken;

        // If tokens are identical after normalization, no conversion required
        if (normalizedBase == normalizedPayment) {
            return baseAmount;
        }

        // Get price oracle
        address oracle = registry.getModuleServiceByAlias(moduleId, 'PriceOracle');
        if (oracle == address(0)) revert PriceFeedNotFound();

        // Get price value in another currency from oracle
        paymentAmount = IPriceOracle(oracle).convertAmount(normalizedBase, normalizedPayment, baseAmount);
        if (paymentAmount == 0) revert InvalidPrice();

        // Эмиссия событий перенесена в отдельный метод emitPriceConvertedEventExternal

        // Value is already stored in paymentAmount (named return)
    }

    /// @notice Checks if a token pair is supported by the oracle
    /// @param moduleId Module identifier
    /// @param baseToken Base token (0x0 or ETH_SENTINEL for native currency)
    /// @param paymentToken Payment token (0x0 or ETH_SENTINEL for native currency)
    /// @return supported Whether the pair is supported
    function isPairSupported(
        bytes32 moduleId,
        address baseToken,
        address paymentToken
    ) external view returns (bool) {
        // Normalize and check if tokens are identical
        address normalizedBase = baseToken.isNative() ? Native.ETH_SENTINEL : baseToken;
        address normalizedPayment = paymentToken.isNative() ? Native.ETH_SENTINEL : paymentToken;

        if (normalizedBase == normalizedPayment) return true;

        // Запрос к оракулу
        address oracle = registry.getModuleServiceByAlias(moduleId, 'PriceOracle');
        return oracle != address(0) && IPriceOracle(oracle).isPairSupported(normalizedBase, normalizedPayment);
    }

    /// @notice Process payment with specified token
    /// @param moduleId Module identifier
    /// @param token Payment token address (0x0 or ETH_SENTINEL for native currency)
    /// @param payer Payer address
    /// @param amount Payment amount
    /// @param signature Signature for payment authorization on behalf of user (if required)
    /// @return netAmount Net amount after fee deduction
    function processPayment(
        bytes32 moduleId,
        address token,
        address payer,
        uint256 amount,
        bytes calldata signature
    ) external payable onlyFeatureOwner nonReentrant whenNotPaused returns (uint256 netAmount) {
        // Preliminary checks to save gas
        if (amount == 0) revert InvalidAmount();
        if (payer == address(0)) revert ZeroAddress();

        // Quick authorization check for direct calls on user's behalf (cheapest path)
        bool isDirectPayment = payer == msg.sender;

        // If not a direct payment, perform more expensive authorization checks
        if (!isDirectPayment) {
            _checkPaymentAuthorization(payer);
        }

        // Check token validity (natively supported or validator allowed)
        if (!token.isNative()) {
            // Only validate non-native tokens through MultiValidator
            address val = registry.getModuleServiceByAlias(moduleId, 'Validator');
            if (val == address(0)) revert ValidatorNotFound();
            if (!IMultiValidator(val).isAllowed(token)) revert NotAllowedToken();
        }

        // Verify signature only if not a direct payment and not a trusted service
        // (most expensive operation is performed last and only when necessary)
        if (!isDirectPayment &&
        !access.hasRole(access.AUTOMATION_ROLE(), msg.sender) &&
        !access.hasRole(access.RELAYER_ROLE(), msg.sender)) {
            _verifyPaymentSignature(moduleId, token, payer, amount, signature);
        }

        // Process payment and fee
        uint256 fee;
        (netAmount, fee) = _executePayment(moduleId, token, payer, amount);

        // Emit event through EventRouter or local event
        _emitPaymentProcessedEvent(moduleId, payer, token, amount, fee, netAmount);
    }

    /// @dev Verifies signature for payment authorization
    function _verifyPaymentSignature(
        bytes32 moduleId,
        address token,
        address payer,
        uint256 amount,
        bytes calldata signature
    ) internal {
        // This function is called only if none of the auto-skip conditions are met
        // Check signature length before hash calculation (gas saving)
        if (signature.length == 0) revert InvalidSignature();

        // Get current nonce but don't update it until signature verification
        // Use module-specific nonce to prevent signature reuse across modules
        uint256 currentNonce = nonces[payer][moduleId];

        // Verify EIP-712 signature
        bytes32 digest = SignatureLib.hashProcessPayment(
            DOMAIN_SEPARATOR,
            payer,
            moduleId,
            token,
            amount,
            currentNonce,
            block.chainid
        );
        if (ECDSA.recover(digest, signature) != payer) revert InvalidSignature();

        // Update nonce only after successful signature verification
        nonces[payer][moduleId] = currentNonce + 1;
    }

    /// @dev Checks authorization for payments on behalf of user
    function _checkPaymentAuthorization(address payer) internal view {
        // Direct payment is always authorized
        if (payer == msg.sender) return;

        // Check if sender has required roles
        if (access.hasRole(access.AUTOMATION_ROLE(), msg.sender) || 
            access.hasRole(access.RELAYER_ROLE(), msg.sender)) {
            return;
        }

        revert NotAuthorized();
    }

    /// @dev Executes payment and calculates fee
    /// @param moduleId Module identifier
    /// @param token Payment token address
    /// @param payer Payer address
    /// @param amount Payment amount
    /// @return netAmount Net amount after fee deduction
    /// @return fee Fee amount collected
    function _executePayment(
        bytes32 moduleId,
        address token,
        address payer,
        uint256 amount
    ) internal returns (uint256 netAmount, uint256 fee) {
        // Check if token is native currency
        if (token.isNative()) {
            return _executeNativePayment(moduleId, payer, amount);
        } else {
            return _executeERC20Payment(moduleId, token, payer, amount);
        }
    }

    /// @dev Processes payment with native currency (ETH)
    function _executeNativePayment(
        bytes32 moduleId,
        address payer,
        uint256 amount
    ) internal returns (uint256 netAmount, uint256 fee) {
        // Verify sufficient ETH was sent
        if (msg.value < amount) revert InsufficientBalance();

        // Calculate fee based on fee manager settings
        fee = _calculateFee(moduleId, Native.ETH_SENTINEL, amount);

        // Validate fee doesn't exceed MAX_FEE_BPS (10%)
        if (fee * 10000 > amount * MAX_FEE_BPS) revert FeeTooHigh();

        // Calculate net amount
        netAmount = amount - fee;

        // Refund excess ETH if necessary
        uint256 excess = msg.value - amount;
        if (excess > 0) {
            (bool refundSuccess,) = payable(payer).call{value: excess}("");
            if (!refundSuccess) revert RefundDisabled();
        }

        return (netAmount, fee);
    }

    /// @dev Processes payment with ERC20 token
    function _executeERC20Payment(
        bytes32 moduleId,
        address token,
        address payer,
        uint256 amount
    ) internal returns (uint256 netAmount, uint256 fee) {
        // Cache addresses and objects to reduce gas costs on SLOAD
        IERC20 tokenContract = IERC20(token);
        address self = address(this);
        address caller = msg.sender;
        address feeManagerAddr = address(feeManager);

        // Transfer tokens from payer to this contract
        tokenContract.safeTransferFrom(payer, self, amount);

        // Calculate fee using the local calculation method for consistency
        fee = _calculateFee(moduleId, token, amount);

        // If fee is greater than zero, collect it using the fee manager
        if (fee > 0) {
            tokenContract.forceApprove(feeManagerAddr, fee);
            feeManager.depositFee(moduleId, token, fee);

            // Reset approval after use
            tokenContract.forceApprove(feeManagerAddr, 0);
        }

        // Calculate net amount and execute transfer
        netAmount = amount - fee;

        // Transfer net amount to caller
        if (netAmount > 0) {
            tokenContract.safeTransfer(caller, netAmount);
        }

        return (netAmount, fee);
    }

    function setRegistry(address newRegistry) external onlyAdmin {
        if (newRegistry == address(0)) revert InvalidAddress();
        registry = IRegistry(newRegistry);
    }

    function setFeeManager(address newManager) external onlyAdmin {
        if (newManager == address(0)) revert InvalidAddress();
        feeManager = CoreFeeManager(newManager);
    }

    function setAccessControl(address newAccess) external onlyAdmin {
        if (newAccess == address(0)) revert InvalidAddress();
        access = AccessControlCenter(newAccess);
    }

    /// @notice Withdraws accumulated native currency fees to specified address
    /// @param to Address to send fees to
    /// @param amount Amount to withdraw (0 for all)
    function withdrawNativeFees(address to, uint256 amount) external onlyAdmin nonReentrant {
        if (to == address(0)) revert ZeroAddress();

        // Default to withdraw all available balance
        uint256 withdrawAmount = amount == 0 ? address(this).balance : amount;

        // Check there are funds to withdraw
        if (withdrawAmount == 0) revert NothingToWithdraw();
        if (withdrawAmount > address(this).balance) revert InsufficientBalance();

        // Transfer fees
        (bool success,) = payable(to).call{value: withdrawAmount}("");
        if (!success) revert RefundDisabled();
    }

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }

    /// @dev Get fee amount for payment
    /// @param moduleId Module identifier
    /// @param token Token address (ETH_SENTINEL for native)
    /// @param amount Gross payment amount
    /// @return feeAmount Total fee amount
    function _calculateFee(
        bytes32 moduleId,
        address token,
        uint256 amount
    ) internal view returns (uint256 feeAmount) {
        // Delegate fee calculation to CoreFeeManager for unified logic
        return feeManager.calculateFee(moduleId, token, amount);
    }

    /// @dev Emit price conversion event
    /// @param moduleId Module identifier
    /// @param baseToken Base token
    /// @param paymentToken Payment token
    /// @param baseAmount Amount in base token
    /// @param paymentAmount Amount in payment token
    function _emitPriceConvertedEvent(
        bytes32 moduleId,
        address baseToken,
        address paymentToken,
        uint256 baseAmount,
        uint256 paymentAmount
    ) internal {
        address router = registry.getModuleService(moduleId, CoreDefs.SERVICE_EVENT_ROUTER);
        if (router != address(0)) {
            IEventRouter(router).route(
                IEventRouter.EventKind.PriceConverted, 
                abi.encode(baseToken, paymentToken, baseAmount, paymentAmount, moduleId, uint16(1))
            );
        } else {
            emit PriceConverted(baseToken, paymentToken, baseAmount, paymentAmount, moduleId, 1);
        }
    }

    /// @dev Emit payment processed event
    /// @param moduleId Module identifier
    /// @param payer Payer address
    /// @param token Token address
    /// @param amount Total payment amount
    /// @param fee Fee amount
    /// @param netAmount Net amount after fee deduction
    function _emitPaymentProcessedEvent(
        bytes32 moduleId,
        address payer,
        address token,
        uint256 amount,
        uint256 fee,
        uint256 netAmount
    ) internal {
        address router = registry.getModuleService(moduleId, CoreDefs.SERVICE_EVENT_ROUTER);
        if (router != address(0)) {
            IEventRouter(router).route(
                IEventRouter.EventKind.PaymentProcessed, 
                abi.encode(payer, token, amount, fee, netAmount, moduleId, uint16(1))
            );
        } else {
            emit PaymentProcessed(payer, token, amount, fee, netAmount, moduleId, 1);
        }
    }

    /// @dev UUPS upgrade authorization
    function _authorizeUpgrade(address newImplementation) internal view override onlyAdmin {
        if (newImplementation == address(0)) revert InvalidImplementation();
    }

    /// @notice Allows contract to receive ETH
    receive() external payable {
        // Silent accept
    }

    /// @notice Fallback function, rejects direct ETH sends without calldata
    fallback() external payable {
        revert("Use processPayment");
    }

    uint256[45] private __gap; // Reduced from 50 to 45 due to added storage variables
}
