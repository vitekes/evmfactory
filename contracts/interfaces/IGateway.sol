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
    ) external payable returns (uint256 netAmount);

    function getPriceInCurrency(
        bytes32 moduleId,
        address baseToken,
        address paymentToken,
        uint256 baseAmount
    ) external view returns (uint256 paymentAmount);

    function isPairSupported(
        bytes32 moduleId,
        address baseToken,
        address paymentToken
    ) external view returns (bool supported);

    function convertAmount(
        bytes32 moduleId,
        address baseToken,
        address paymentToken,
        uint256 baseAmount
    ) external view returns (uint256 paymentAmount);
}
