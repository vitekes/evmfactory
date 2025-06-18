// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IGateway
/// @notice Abstraction for payment gateways
interface IGateway {
    function processPayment(
        bytes32 moduleId,
        address token,
        address payer,
        uint256 amount,
        bytes calldata signature
    ) external returns (uint256 netAmount);
}
