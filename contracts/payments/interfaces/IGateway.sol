// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IGateway
/// @notice Abstraction for payment gateways
interface IGateway {
    /// @notice Process payment with specified token
    /// @param moduleId Module identifier
    /// @param token Payment token address (0x0 for native currency)
    /// @param payer Payer address
    /// @param amount Payment amount
    /// @param signature Signature for payment authorization on behalf of user
    /// @return netAmount Net amount after fee deduction
    function processPayment(
        bytes32 moduleId,
        address token,
        address payer,
        uint256 amount,
        bytes calldata signature
    ) external payable returns (uint256 netAmount);

    /// @notice Gets the price in specified currency
    /// @param moduleId Module ID
    /// @param baseToken Base token (0x0 for native currency)
    /// @param paymentToken Payment token (0x0 for native currency)
    /// @param baseAmount Amount in base token
    /// @return paymentAmount Amount in payment token
    function getPriceInCurrency(
        bytes32 moduleId,
        address baseToken,
        address paymentToken,
        uint256 baseAmount
    ) external view returns (uint256 paymentAmount);
// SPDX-License-Identifier: MIT

    /// @notice Checks if a token pair is supported by the oracle
    /// @param moduleId Module identifier
    /// @param baseToken Base token (0x0 for native currency)
    /// @param paymentToken Payment token (0x0 for native currency)
    /// @return supported Whether the pair is supported
    function isPairSupported(
        bytes32 moduleId,
        address baseToken,
        address paymentToken
    ) external view returns (bool supported);

    /// @notice Converts amount from one token to another
    /// @param moduleId Module ID
    /// @param baseToken Base token (0x0 for native currency)
    /// @param paymentToken Payment token (0x0 for native currency)
    /// @param baseAmount Amount in base token
    /// @return paymentAmount Amount in payment token
    function convertAmount(
        bytes32 moduleId,
        address baseToken,
        address paymentToken,
        uint256 baseAmount
    ) external view returns (uint256 paymentAmount);

    /// @notice Get the net amount after fees for a given payment
    /// @param moduleId Module identifier
    /// @param token Token being used for payment
    /// @param amount Gross amount
    /// @return netAmount Net amount after fees
    function getNetAmount(
        bytes32 moduleId,
        address token,
        uint256 amount
    ) external view returns (uint256 netAmount);

    /// @notice Get the fee amount for a given payment
    /// @param moduleId Module identifier
    /// @param token Token being used for payment
    /// @param amount Gross amount
    /// @return feeAmount Fee amount
    function getFeeAmount(
        bytes32 moduleId,
        address token,
        uint256 amount
    ) external view returns (uint256 feeAmount);
}
