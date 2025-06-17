// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../core/Registry.sol";
import "../../core/PaymentGateway.sol";

/// @title SubscriptionManager
/// @notice Example subscription manager that charges users via PaymentGateway.
contract SubscriptionManager {
    Registry public immutable registry;
    bytes32 public constant MODULE_ID = keccak256("Subscriptions");

    mapping(address => uint256) public paidAmount;

    event Subscribed(address indexed user, uint256 amount, address token);

    constructor(address _registry) {
        registry = Registry(_registry);
    }

    /// @notice Charge user for subscription using PaymentGateway
    function subscribe(address token, uint256 amount) external {
        PaymentGateway(
            registry.getModuleService(MODULE_ID, keccak256(bytes("PaymentGateway")))
        ).processPayment(MODULE_ID, token, msg.sender, amount);

        paidAmount[msg.sender] += amount;
        emit Subscribed(msg.sender, amount, token);
    }
}
