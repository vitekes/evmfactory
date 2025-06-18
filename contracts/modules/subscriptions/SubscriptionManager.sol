// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../core/Registry.sol";
import "../../core/PaymentGateway.sol";
import "../../core/AccessControlCenter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SubscriptionManager
/// @notice Example subscription manager that charges users via PaymentGateway.
contract SubscriptionManager {
    using SafeERC20 for IERC20;

    Registry public immutable registry;
    bytes32 public immutable MODULE_ID;

    struct Plan {
        address token;
        uint256 price;
        uint256 period;
    }

    mapping(uint256 => Plan) public plans;
    uint256 public nextPlanId;

    mapping(address => uint256) public userPlan;
    mapping(address => uint256) public nextPayment;
    mapping(address => uint256) public paidAmount;

    address public owner;

    event PlanCreated(uint256 id, address token, uint256 price, uint256 period);
    event Subscribed(address indexed user, uint256 planId, uint256 amount, address token);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor(address _registry, address paymentGateway, bytes32 moduleId) {
        registry = Registry(_registry);
        owner = msg.sender;
        MODULE_ID = moduleId;
        registry.setModuleServiceAlias(MODULE_ID, "PaymentGateway", paymentGateway);

        AccessControlCenter acl = AccessControlCenter(
            registry.getCoreService(keccak256("AccessControlCenter"))
        );
        bytes32[] memory roles = new bytes32[](2);
        roles[0] = acl.MODULE_ROLE();
        roles[1] = acl.FEATURE_OWNER_ROLE();
        acl.grantMultipleRoles(address(this), roles);
    }

    /// @notice Add a new subscription plan
    function createPlan(address token, uint256 price, uint256 period) external onlyOwner returns (uint256 id) {
        id = nextPlanId++;
        plans[id] = Plan(token, price, period);
        emit PlanCreated(id, token, price, period);
    }

    /// @notice Subscribe user to a plan and charge first payment
    function subscribe(uint256 planId) external {
        Plan memory p = plans[planId];
        require(p.token != address(0), "plan not found");

        uint256 netAmount = PaymentGateway(
            registry.getModuleService(MODULE_ID, keccak256(bytes("PaymentGateway")))
        ).processPayment(MODULE_ID, p.token, msg.sender, p.price, "");

        IERC20(p.token).safeTransfer(owner, netAmount);

        userPlan[msg.sender] = planId;
        nextPayment[msg.sender] = block.timestamp + p.period;
        paidAmount[msg.sender] += netAmount;

        emit Subscribed(msg.sender, planId, p.price, p.token);
    }

    /// @notice Charge recurring payment, callable by keeper/relayer
    function charge(address user) external {
        uint256 planId = userPlan[user];
        Plan memory p = plans[planId];
        require(p.token != address(0), "no plan");
        require(block.timestamp >= nextPayment[user], "not due");

        uint256 netAmount = PaymentGateway(
            registry.getModuleService(MODULE_ID, keccak256(bytes("PaymentGateway")))
        ).processPayment(MODULE_ID, p.token, user, p.price, "");

        IERC20(p.token).safeTransfer(owner, netAmount);

        nextPayment[user] = block.timestamp + p.period;
        paidAmount[user] += netAmount;

        emit Subscribed(user, planId, p.price, p.token);
    }

    function chargeBatch(address[] calldata users) external {
        for (uint256 i = 0; i < users.length; i++) {
            charge(users[i]);
        }
    }

    function unsubscribe() external {
        userPlan[msg.sender] = 0;
        nextPayment[msg.sender] = 0;
    }
}
