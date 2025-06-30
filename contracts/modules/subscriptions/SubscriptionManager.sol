// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../../core/Registry.sol';
import '../../interfaces/IGateway.sol';
import '../../core/AccessControlCenter.sol';
import '../../shared/AccessManaged.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import '../../interfaces/IPermit2.sol';
import '../../lib/SignatureLib.sol';
import '../../interfaces/CoreDefs.sol';
import '../../errors/Errors.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

/// @title Subscription Manager
/// @notice Handles recurring payments with off-chain plan creation using EIP-712
contract SubscriptionManager is AccessManaged, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    /// @notice Core registry used for service discovery
    Registry public immutable registry;
    /// @notice Identifier of the module within the registry
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
    bytes32 public DOMAIN_SEPARATOR;

    /// @notice Emitted when a user subscribes to a plan
    /// @param user Subscriber address
    /// @param planHash Hash of the plan parameters
    /// @param amount Price paid by the user
    /// @param token Payment token address
    event Subscribed(address indexed user, bytes32 indexed planHash, uint256 amount, address token);
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

    /// @notice Initializes the subscription manager and registers services
    /// @param _registry Address of the core Registry contract
    /// @param moduleId Unique module identifier
    constructor(
        address _registry,
        address /* paymentGateway */,
        bytes32 moduleId
    ) AccessManaged(Registry(_registry).getCoreService(keccak256('AccessControlCenter'))) {
        registry = Registry(_registry);
        MODULE_ID = moduleId;
        // Service registration handled externally after deployment

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(uint256 chainId,address verifyingContract)'),
                block.chainid,
                address(this)
            )
        );

        // Role assignment should be done outside the constructor

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
        bytes32 planHash = hashPlan(plan);
        if (planHash.recover(sigMerchant) != plan.merchant) revert InvalidSignature();
        if (!(plan.expiry == 0 || plan.expiry >= block.timestamp)) revert Expired();
        bool chainAllowed = false;
        for (uint256 i = 0; i < plan.chainIds.length; i++) {
            if (plan.chainIds[i] == block.chainid) {
                chainAllowed = true;
                break;
            }
        }
        if (!chainAllowed) revert InvalidChain();

        if (permitSig.length > 0) {
            (uint256 deadline, uint8 v, bytes32 r, bytes32 s) = abi.decode(
                permitSig,
                (uint256, uint8, bytes32, bytes32)
            );
            address gateway = registry.getModuleService(MODULE_ID, CoreDefs.SERVICE_PAYMENT_GATEWAY);
            try IERC20Permit(plan.token).permit(msg.sender, gateway, plan.price, deadline, v, r, s) {
                // ok
            } catch {
                address permit2 = registry.getModuleService(MODULE_ID, keccak256(bytes('Permit2')));
                bytes memory data = abi.encodeWithSelector(
                    IPermit2.permitTransferFrom.selector,
                    IPermit2.PermitTransferFrom({
                        permitted: IPermit2.TokenPermissions({token: plan.token, amount: plan.price}),
                        nonce: 0,
                        deadline: deadline
                    }),
                    IPermit2.SignatureTransferDetails({to: gateway, requestedAmount: plan.price}),
                    msg.sender,
                    abi.encodePacked(r, s, v)
                );
                (bool ok, ) = permit2.call(data);
                if (!ok) revert PermitFailed();
            }
        }

        uint256 netAmount = IGateway(registry.getModuleService(MODULE_ID, CoreDefs.SERVICE_PAYMENT_GATEWAY))
            .processPayment(MODULE_ID, plan.token, msg.sender, plan.price, '');

        IERC20(plan.token).safeTransfer(plan.merchant, netAmount);

        if (plans[planHash].merchant == address(0)) {
            plans[planHash] = plan;
        }
        subscribers[msg.sender] = Subscriber({nextBilling: block.timestamp + plan.period, planHash: planHash});

        emit Subscribed(msg.sender, planHash, plan.price, plan.token);
    }

    /// @dev Restricts calls to automation addresses configured in ACL
    modifier onlyAutomation() {
        AccessControlCenter acl = AccessControlCenter(registry.getCoreService(keccak256('AccessControlCenter')));
        if (!acl.hasRole(acl.AUTOMATION_ROLE(), msg.sender)) revert NotAutomation();
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

        uint256 netAmount = IGateway(registry.getModuleService(MODULE_ID, CoreDefs.SERVICE_PAYMENT_GATEWAY))
            .processPayment(MODULE_ID, plan.token, user, plan.price, '');

        IERC20(plan.token).safeTransfer(plan.merchant, netAmount);

        s.nextBilling += plan.period;

        emit SubscriptionCharged(user, s.planHash, plan.price, s.nextBilling);
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
    function setBatchLimit(uint16 newLimit) external onlyRole(AccessControlCenter(_ACC).GOVERNOR_ROLE()) {
        batchLimit = newLimit;
    }

    /// @notice Cancel the caller's subscription and delete their state.
    /// @dev Emits {Unsubscribed} and {PlanCancelled}.
    function unsubscribe() external {
        Subscriber memory s = subscribers[msg.sender];
        delete subscribers[msg.sender];
        emit Unsubscribed(msg.sender, s.planHash);
        emit PlanCancelled(msg.sender, s.planHash, block.timestamp);
    }
}
