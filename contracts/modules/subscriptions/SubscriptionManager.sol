// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../../core/interfaces/ICoreSystem.sol';
import '../../payments/interfaces/IGateway.sol';
import '../../payments/interfaces/IPriceOracle.sol';
import '../../external/IPermit2.sol';
import '../../lib/SignatureLib.sol';
import '../../shared/CoreDefs.sol';
import '../../errors/Errors.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

/// @title Subscription Manager
/// @notice Handles recurring payments with off-chain plan creation using EIP-712
/// @dev Uses PaymentGateway (IGateway) for payment processing and token conversion
contract SubscriptionManager is ReentrancyGuard {
    // Core system reference
    ICoreSystem public immutable core;

    /// @notice Убеждается, что вызывающий имеет роль администратора
    modifier onlyAdmin() {
        if (!core.hasRole(0x00, msg.sender))
            revert NotAdmin();
        _;
    }

    /// @notice Убеждается, что вызывающий имеет роль владельца фичи
    modifier onlyFeatureOwner() {
        bytes32 role = CoreDefs.FEATURE_OWNER_ROLE;
        if (!core.hasRole(role, msg.sender))
            revert NotFeatureOwner();
        _;
    }

    /// @notice Убеждается, что вызывающий имеет роль оператора
    modifier onlyOperator() {
        bytes32 role = CoreDefs.OPERATOR_ROLE;
        if (!core.hasRole(role, msg.sender))
            revert NotOperator();
        _;
    }

    /// @notice Проверяет наличие определенной роли
    modifier onlyRole(bytes32 role) {
        if (!core.hasRole(role, msg.sender)) revert Forbidden();
        _;
    }

    /// @notice Проверяет, является ли аккаунт оператором
    /// @param account Проверяемый адрес
    /// @return Является ли аккаунт оператором
    function isOperator(address account) external view returns (bool) {
        return core.isOperator(account);
    }

    /// @notice Получает список операторов
    /// @return Массив адресов операторов
    function getOperators() external view returns (address[] memory) {
        return core.getOperators();
    }

    /// @notice Назначает роль оператора указанному адресу
    /// @param account Адрес, которому будет назначена роль
    function grantOperatorRole(address account) external onlyAdmin {
        core.grantOperatorRole(account);
    }

    /// @notice Отзывает роль оператора у указанного адреса
    /// @param account Адрес, у которого будет отозвана роль
    function revokeOperatorRole(address account) external onlyAdmin {
        core.revokeOperatorRole(account);
    }
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    /// @notice Identifier of the module within the core system
    bytes32 public immutable MODULE_ID;

    /// @notice Subscription data for a user
    struct Subscriber {
        uint256 nextBilling; // timestamp of the next charge
        bytes32 planHash; // plan this user is subscribed to
    }

    /// @notice Registered plans by their hash
    mapping(bytes32 => SignatureLib.Plan) public plans;
    /// @notice Active subscriber info mapped by user address
    mapping(address => Subscriber) public subscribers;

    /// @notice Maximum number of users to charge in a single batch. 0 disables the limit.
    uint16 public batchLimit;

    /// @notice EIP-712 domain separator for plan signatures
    bytes32 public immutable DOMAIN_SEPARATOR;

    /// @notice Emitted when a user cancels their subscription
    /// @param user Subscriber address
    /// @param planHash Hash of the plan
    event Unsubscribed(address indexed user, bytes32 indexed planHash);
    /// @notice Emitted when a plan is cancelled
    /// @param user Subscriber address
    /// @param planHash Hash of the plan
    /// @param ts Timestamp of cancellation
    event PlanCancelled(address indexed user, bytes32 indexed planHash, uint256 ts);
    /// @notice Emitted after a successful recurring charge
    /// @param user Subscriber address
    /// @param planHash Hash of the plan
    /// @param amount Amount charged
    /// @param nextBilling Next timestamp for payment
    event SubscriptionCharged(address indexed user, bytes32 indexed planHash, uint256 amount, uint256 nextBilling);
    /// @notice Emitted when a subscription is created
    /// @param subscriptionId Subscription ID
    /// @param owner Owner address
    /// @param planId Plan ID
    /// @param startTime Start timestamp
    /// @param endTime End timestamp
    /// @param moduleId Module ID
    event SubscriptionCreated(
        uint256 subscriptionId,
        address owner,
        bytes32 planId,
        uint256 startTime,
        uint256 endTime,
        bytes32 moduleId
    );
    /// @notice Emitted when a subscription is renewed
    /// @param subscriptionId Subscription ID
    /// @param newEndTime New end timestamp
    /// @param moduleId Module ID
    event SubscriptionRenewed(uint256 subscriptionId, uint256 newEndTime, bytes32 moduleId);
    /// @notice Emitted when a subscription is cancelled
    /// @param subscriptionId Subscription ID
    /// @param moduleId Module ID
    event SubscriptionCancelled(uint256 subscriptionId, bytes32 moduleId);

    /// @notice Initializes the subscription manager and registers services
    /// @param _core Address of the CoreSystem contract
    /// @param paymentGateway Address of the payment gateway implementing IGateway
    /// @param moduleId Unique module identifier
    constructor(
        address _core,
        address paymentGateway,
        bytes32 moduleId
    ) {
        // Check inputs validity
        if (_core == address(0)) revert ZeroAddress();
        if (paymentGateway == address(0)) revert InvalidAddress();

        core = ICoreSystem(_core);
        MODULE_ID = moduleId;

        // Initialize DOMAIN_SEPARATOR as immutable value
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(uint256 chainId,address verifyingContract)'),
                block.chainid,
                address(this)
            )
        );

        batchLimit = 0;
    }

    /// @notice Calculates the EIP-712 hash of a subscription plan
    /// @param plan Plan parameters
    /// @return Hash to be signed by the merchant
    function hashPlan(SignatureLib.Plan calldata plan) public view returns (bytes32) {
        return SignatureLib.hashPlan(plan, DOMAIN_SEPARATOR);
    }

    /// @notice Subscribe caller to a plan
    /// @param plan Plan parameters signed by the merchant
    /// @param sigMerchant Merchant signature over the plan
    /// @param permitSig Optional permit or Permit2 signature for token spending
    function subscribe(
        SignatureLib.Plan calldata plan,
        bytes calldata sigMerchant,
        bytes calldata permitSig
    ) external nonReentrant {
        _subscribe(plan, sigMerchant, permitSig, plan.token, plan.price);
    }

    /// @notice Subscribe caller to a plan using an alternative token
    /// @param plan Plan parameters signed by the merchant
    /// @param sigMerchant Merchant signature over the plan
    /// @param permitSig Optional permit or Permit2 signature for token spending
    /// @param paymentToken Alternative token to use for payment
    /// @param maxPaymentAmount Maximum amount to pay (0 to disable check)
    function subscribeWithToken(
        SignatureLib.Plan calldata plan,
        bytes calldata sigMerchant,
        bytes calldata permitSig,
        address paymentToken,
        uint256 maxPaymentAmount
    ) external nonReentrant {
        // Cheap pre-checks
        if (paymentToken == address(0)) revert InvalidAddress();
        if (plan.price == 0) revert InvalidAmount();
        if (plan.merchant == address(0)) revert ZeroAddress();

        // If tokens match use the regular path
        if (paymentToken == plan.token) {
            _subscribe(plan, sigMerchant, permitSig, plan.token, plan.price);
            return;
        }

        // Ensure gateway is registered before heavy logic
        address gatewayAddress = core.getModuleService(MODULE_ID, CoreDefs.SERVICE_PAYMENT_GATEWAY);
        if (gatewayAddress == address(0)) revert PaymentGatewayNotRegistered();
        IGateway gateway = IGateway(gatewayAddress);

        // Verify token pair support
        if (!gateway.isPairSupported(MODULE_ID, plan.token, paymentToken)) revert UnsupportedPair();

        // Calculate payment amount in chosen token
        uint256 paymentAmount = gateway.convertAmount(MODULE_ID, plan.token, paymentToken, plan.price);
        if (paymentAmount == 0) revert InvalidPrice();

        // Ensure amount does not exceed limit
        if (maxPaymentAmount > 0 && paymentAmount > maxPaymentAmount) {
            revert PriceExceedsMaximum();
        }

        _subscribe(plan, sigMerchant, permitSig, paymentToken, paymentAmount);
    }

    /// @notice Internal function to handle subscription logic
    /// @param plan Plan parameters signed by the merchant
    /// @param sigMerchant Merchant signature over the plan
    /// @param permitSig Optional permit or Permit2 signature for token spending
    /// @param paymentToken Token to use for payment
    /// @param paymentAmount Amount to pay in the specified token
    function _subscribe(
        SignatureLib.Plan calldata plan,
        bytes calldata sigMerchant,
        bytes calldata permitSig,
        address paymentToken,
        uint256 paymentAmount
    ) internal {
        // Basic parameter checks first
        if (paymentAmount == 0) revert InvalidAmount();
        if (paymentToken == address(0)) revert ZeroAddress();
        if (plan.merchant == address(0)) revert ZeroAddress();

        // Check plan expiry
        if (!(plan.expiry == 0 || plan.expiry >= block.timestamp)) revert Expired();

        // Verify chain support
        bool chainAllowed = false;
        uint256 chainIdsLen = plan.chainIds.length;
        for (uint256 i = 0; i < chainIdsLen; i++) {
            if (plan.chainIds[i] == block.chainid) {
                chainAllowed = true;
                break;
            }
        }
        if (!chainAllowed) revert InvalidChain();

        // Ensure payment gateway is registered
        if (core.getModuleServiceByAlias(MODULE_ID, 'PaymentGateway') == address(0))
            revert PaymentGatewayNotRegistered();

        // Compute plan hash before signature check
        bytes32 planHash = hashPlan(plan);

        // Verify signature last (expensive)
        if (planHash.recover(sigMerchant) != plan.merchant) revert InvalidSignature();

        // Save plan and create subscriber before external calls
        if (plans[planHash].merchant == address(0)) {
            plans[planHash] = plan;
        }
        subscribers[msg.sender] = Subscriber({nextBilling: block.timestamp + plan.period, planHash: planHash});

        if (permitSig.length > 0) {
            (uint256 deadline, uint8 v, bytes32 r, bytes32 s) = abi.decode(
                permitSig,
                (uint256, uint8, bytes32, bytes32)
            );
            address paymentGateway = core.getModuleServiceByAlias(MODULE_ID, 'PaymentGateway');
            try IERC20Permit(paymentToken).permit(msg.sender, paymentGateway, paymentAmount, deadline, v, r, s) {
                // ok
            } catch {
                address permit2 = core.getModuleServiceByAlias(MODULE_ID, 'Permit2');
                bytes memory data = abi.encodeWithSelector(
                    IPermit2.permitTransferFrom.selector,
                    IPermit2.PermitTransferFrom({
                        permitted: IPermit2.TokenPermissions({token: paymentToken, amount: paymentAmount}),
                        nonce: 0,
                        deadline: deadline
                    }),
                    IPermit2.SignatureTransferDetails({to: paymentGateway, requestedAmount: paymentAmount}),
                    msg.sender,
                    abi.encodePacked(r, s, v)
                );
                (bool ok, ) = permit2.call(data);
                if (!ok) revert PermitFailed();
            }
        }

        // Get gateway address for payment
        address gateway = core.getModuleServiceByAlias(MODULE_ID, 'PaymentGateway');
        if (gateway == address(0)) revert PaymentGatewayNotRegistered();

        // Process payment via gateway
        uint256 netAmount = IGateway(gateway).processPayment(MODULE_ID, paymentToken, msg.sender, paymentAmount, '');

        // Transfer funds to merchant
        IERC20(paymentToken).safeTransfer(plan.merchant, netAmount);

        // Emit event directly
        emit SubscriptionCreated(
            uint256(planHash), // Use plan hash as subscription ID
            msg.sender,
            planHash,
            block.timestamp,
            block.timestamp + plan.period,
            MODULE_ID
        );
    }

    /// @dev Restricts calls to automation addresses configured in ACL
    modifier onlyAutomation() {
        bytes32 role = keccak256('AUTOMATION_ROLE');
        if (!core.hasRole(role, msg.sender)) revert NotAutomation();
        _;
    }

    /// @notice Charge a user according to their plan
    /// @param user Address of the subscriber to charge
    function charge(address user) public onlyAutomation nonReentrant {
        _charge(user);
    }

    function _charge(address user) internal {
        Subscriber storage s = subscribers[user];
        SignatureLib.Plan memory plan = plans[s.planHash];
        if (plan.merchant == address(0)) revert NoPlan();
        if (block.timestamp < s.nextBilling) revert NotDue();

        // Update state before external call (CEI pattern)
        uint256 nextBillingTime = s.nextBilling + plan.period;
        s.nextBilling = nextBillingTime;

        // Emit events directly
        emit SubscriptionRenewed(uint256(s.planHash), nextBillingTime, MODULE_ID);
        emit SubscriptionCharged(user, s.planHash, plan.price, nextBillingTime);

        // Get gateway address for payment
        address gateway = core.getModuleServiceByAlias(MODULE_ID, 'PaymentGateway');
        if (gateway == address(0)) revert PaymentGatewayNotRegistered();

        // Process payment via gateway
        uint256 netAmount = IGateway(gateway).processPayment(MODULE_ID, plan.token, user, plan.price, '');

        // Transfer funds to merchant
        IERC20(plan.token).safeTransfer(plan.merchant, netAmount);
    }

    /// @notice Charge multiple subscribers in a single transaction.
    /// @dev Processes up to `batchLimit` addresses if the provided array is
    ///      larger. Reverts with {NoPlan} or {NotDue} for each user that cannot
    ///      be charged.
    /// @param users Array of subscriber addresses to charge.
    function chargeBatch(address[] calldata users) external onlyAutomation {
        uint256 limit = users.length;
        if (batchLimit > 0 && limit > batchLimit) {
            limit = batchLimit;
        }
        uint256 len = limit;
        for (uint256 i = 0; i < len; ) {
            _charge(users[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Sets the maximum batch charge limit
    /// @param newLimit New limit value (0 to disable)
    function setBatchLimit(uint16 newLimit) external onlyRole(keccak256('GOVERNOR_ROLE')) {
        batchLimit = newLimit;
    }

    /// @notice Backwards-compatible method
    /// @param plan Subscription plan signed by the merchant
    /// @param sigMerchant Merchant signature
    /// @param permitSig Optional permit signature
    /// @param paymentToken Alternative payment token
    function subscribeWithToken(
        SignatureLib.Plan calldata plan,
        bytes calldata sigMerchant,
        bytes calldata permitSig,
        address paymentToken
    ) external nonReentrant {
        // Call new version with disabled max amount check
        this.subscribeWithToken(plan, sigMerchant, permitSig, paymentToken, 0);
    }

    /// @notice Get payment amount for a plan in the specified token
    /// @dev Uses PaymentGateway for currency conversion
    /// @param plan Plan to calculate from
    /// @param paymentToken Token to pay with
    /// @return paymentAmount Amount in the desired token
    function getPlanPaymentInToken(
        SignatureLib.Plan calldata plan,
        address paymentToken
    ) external view returns (uint256 paymentAmount) {
        if (paymentToken == address(0)) revert InvalidAddress();
        if (paymentToken == plan.token) {
            return plan.price;
        }

        // Convert using PaymentGateway
        address gatewayAddress = core.getModuleServiceByAlias(MODULE_ID, 'PaymentGateway');
        if (gatewayAddress == address(0)) revert PaymentGatewayNotRegistered();

        IGateway paymentGateway = IGateway(gatewayAddress);

        // Check token pair support
        if (!paymentGateway.isPairSupported(MODULE_ID, plan.token, paymentToken)) revert UnsupportedPair();

        // Convert amount
        uint256 result = paymentGateway.convertAmount(MODULE_ID, plan.token, paymentToken, plan.price);
        if (result == 0) revert InvalidPrice();
        return result;
    }

    /// @notice Cancel the caller's subscription and delete their state.
    /// @dev Emits {Unsubscribed} and {PlanCancelled}.
    function unsubscribe() external {
        Subscriber memory s = subscribers[msg.sender];
        // Ensure subscription exists
        if (s.planHash == bytes32(0)) revert NoPlan();

        delete subscribers[msg.sender];

        // Emit events directly
        emit SubscriptionCancelled(uint256(s.planHash), MODULE_ID);
        emit Unsubscribed(msg.sender, s.planHash);
        emit PlanCancelled(msg.sender, s.planHash, block.timestamp);
    }
}
