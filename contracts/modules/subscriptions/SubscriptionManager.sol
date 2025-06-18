// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../core/Registry.sol";
import "../../interfaces/IGateway.sol";
import "../../core/AccessControlCenter.sol";
import "../../shared/AccessManaged.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../../lib/SignatureLib.sol";

/// @title Subscription Manager
/// @notice Handles recurring payments with off-chain plan creation using EIP-712
contract SubscriptionManager is AccessManaged {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;
    /// @notice Thrown when merchant signature does not match the plan
    error InvalidSignature();

    /// @notice Core registry used for service discovery
    Registry public immutable registry;
    /// @notice Identifier of the module within the registry
    bytes32 public immutable MODULE_ID;



    /// @notice Subscription data for a user
    struct Subscriber {
        uint256 nextBilling; // timestamp of the next charge
        bytes32 planHash;    // plan this user is subscribed to
    }

    /// @notice Registered plans by their hash
    mapping(bytes32 => SignatureLib.Plan) public plans;
    /// @notice Active subscriber info mapped by user address
    mapping(address => Subscriber) public subscribers;

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
    /// @notice Emitted after a successful recurring charge
    /// @param user Subscriber address
    /// @param planHash Hash of the plan
    /// @param amount Amount charged
    /// @param nextBilling Next timestamp for payment
    event SubscriptionCharged(address indexed user, bytes32 indexed planHash, uint256 amount, uint256 nextBilling);

    /// @notice Initializes the subscription manager and registers services
    /// @param _registry Address of the core Registry contract
    /// @param paymentGateway Payment gateway used to process fees
    /// @param moduleId Unique module identifier
    constructor(address _registry, address paymentGateway, bytes32 moduleId)
        AccessManaged(Registry(_registry).getCoreService(keccak256("AccessControlCenter")))
    {
        registry = Registry(_registry);
        MODULE_ID = moduleId;
        registry.setModuleServiceAlias(MODULE_ID, "PaymentGateway", paymentGateway);

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(uint256 chainId,address verifyingContract)"),
                block.chainid,
                address(this)
            )
        );

        AccessControlCenter acl = AccessControlCenter(_ACC);
        bytes32[] memory roles = new bytes32[](2);
        roles[0] = acl.MODULE_ROLE();
        roles[1] = acl.FEATURE_OWNER_ROLE();
        _grantSelfRoles(roles);
    }

    /// @notice Calculates the EIP-712 hash of a subscription plan
    /// @param plan Plan parameters
    /// @return Hash to be signed by the merchant
    function hashPlan(SignatureLib.Plan calldata plan) public view returns (bytes32) {
        bytes32 structHash = SignatureLib.hashPlan(plan);
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
    }

    /// @notice Subscribe caller to a plan
    /// @param plan Plan parameters signed by the merchant
    /// @param sigMerchant Merchant signature over the plan
    /// @param permitSig Optional permit or Permit2 signature for token spending
    function subscribe(SignatureLib.Plan calldata plan, bytes calldata sigMerchant, bytes calldata permitSig) external {
        bytes32 planHash = hashPlan(plan);
        if (planHash.recover(sigMerchant) != plan.merchant) revert InvalidSignature();
        require(plan.expiry == 0 || plan.expiry >= block.timestamp, "expired");
        bool chainAllowed = false;
        for (uint256 i = 0; i < plan.chainIds.length; i++) {
            if (plan.chainIds[i] == block.chainid) {
                chainAllowed = true;
                break;
            }
        }
        require(chainAllowed, "invalid chain");

        if (permitSig.length > 0) {
            bytes4 selector;
            assembly {
                selector := shr(224, calldataload(permitSig.offset))
            }
            address target = plan.token;
            if (selector != IERC20Permit.permit.selector) {
                target = registry.getModuleService(
                    MODULE_ID,
                    keccak256(bytes("Permit2"))
                );
            }
            (bool ok, ) = target.call(permitSig);
            require(ok, "permit failed");
        }

        uint256 netAmount = IGateway(
            registry.getModuleService(MODULE_ID, keccak256(bytes("PaymentGateway")))
        ).processPayment(MODULE_ID, plan.token, msg.sender, plan.price, "");

        IERC20(plan.token).safeTransfer(plan.merchant, netAmount);

        if (plans[planHash].merchant == address(0)) {
            plans[planHash] = plan;
        }
        subscribers[msg.sender] = Subscriber({ nextBilling: block.timestamp + plan.period, planHash: planHash });

        emit Subscribed(msg.sender, planHash, plan.price, plan.token);
    }

    /// @dev Restricts calls to automation addresses configured in ACL
    modifier onlyAutomation() {
        AccessControlCenter acl = AccessControlCenter(
            registry.getCoreService(keccak256("AccessControlCenter"))
        );
        require(acl.hasRole(acl.AUTOMATION_ROLE(), msg.sender), "not automation");
        _;
    }

    /// @notice Charge a user according to their plan
    /// @param user Address of the subscriber to charge
    function charge(address user) public onlyAutomation {
        Subscriber storage s = subscribers[user];
        SignatureLib.Plan memory plan = plans[s.planHash];
        require(plan.merchant != address(0), "no plan");
        require(block.timestamp >= s.nextBilling, "not due");

        uint256 netAmount = IGateway(
            registry.getModuleService(MODULE_ID, keccak256(bytes("PaymentGateway")))
        ).processPayment(MODULE_ID, plan.token, user, plan.price, "");

        IERC20(plan.token).safeTransfer(plan.merchant, netAmount);

        s.nextBilling += plan.period;

        emit SubscriptionCharged(user, s.planHash, plan.price, s.nextBilling);
    }

    /// @notice Charge multiple users in a single transaction
    /// @param users List of subscriber addresses
    function chargeBatch(address[] calldata users) external onlyAutomation {
        require(users.length <= 50, "batch limit");
        unchecked {
            for (uint256 i = 0; i < users.length; i++) {
                charge(users[i]);
            }
        }
    }

    /// @notice Cancel caller's subscription
    function unsubscribe() external {
        Subscriber memory s = subscribers[msg.sender];
        delete subscribers[msg.sender];
        emit Unsubscribed(msg.sender, s.planHash);
    }
}

