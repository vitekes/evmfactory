// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../core/Registry.sol";
import "../../interfaces/IGateway.sol";
import "../../core/AccessControlCenter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../../lib/SignatureLib.sol";

/// @title SubscriptionManager
/// @notice Subscription system with off-chain plan creation using EIP-712
contract SubscriptionManager {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;
    error InvalidSignature();

    Registry public immutable registry;
    bytes32 public immutable MODULE_ID;



    struct Subscriber {
        uint256 nextBilling;
        bytes32 planHash;
    }

    mapping(bytes32 => SignatureLib.Plan) public plans;
    mapping(address => Subscriber) public subscribers;

    bytes32 public DOMAIN_SEPARATOR;

    event Subscribed(address indexed user, bytes32 indexed planHash, uint256 amount, address token);
    event Unsubscribed(address indexed user, bytes32 indexed planHash);
    event SubscriptionCharged(address indexed user, bytes32 indexed planHash, uint256 amount, uint256 nextBilling);

    constructor(address _registry, address paymentGateway, bytes32 moduleId) {
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

        AccessControlCenter acl = AccessControlCenter(
            registry.getCoreService(keccak256("AccessControlCenter"))
        );
        bytes32[] memory roles = new bytes32[](2);
        roles[0] = acl.MODULE_ROLE();
        roles[1] = acl.FEATURE_OWNER_ROLE();
        acl.grantMultipleRoles(address(this), roles);
    }

    function hashPlan(SignatureLib.Plan calldata plan) public view returns (bytes32) {
        bytes32 structHash = SignatureLib.hashPlan(plan);
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
    }

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

    modifier onlyAutomation() {
        AccessControlCenter acl = AccessControlCenter(
            registry.getCoreService(keccak256("AccessControlCenter"))
        );
        require(acl.hasRole(acl.AUTOMATION_ROLE(), msg.sender), "not automation");
        _;
    }

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

    function chargeBatch(address[] calldata users) external onlyAutomation {
        require(users.length <= 50, "batch limit");
        unchecked {
            for (uint256 i = 0; i < users.length; i++) {
                charge(users[i]);
            }
        }
    }

    function unsubscribe() external {
        Subscriber memory s = subscribers[msg.sender];
        delete subscribers[msg.sender];
        emit Unsubscribed(msg.sender, s.planHash);
    }
}

