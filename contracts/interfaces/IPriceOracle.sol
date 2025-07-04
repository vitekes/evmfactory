// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title Price Oracle Interface
/// @notice Interface for price oracles to convert between token amounts
interface IPriceOracle {
    /// @notice Get price for a token pair
    /// @param token Token to get price for
    /// @param baseToken Base token to compare against
    /// @return price Price with decimals
    /// @return decimals Number of decimals in the price
    function getPrice(address token, address baseToken) external view returns (uint256 price, uint8 decimals);

    /// @notice Convert amount from one token to another
    /// @param fromToken Token to convert from
    /// @param toToken Token to convert to
    /// @param amount Amount to convert
    /// @return convertedAmount Amount in target token
    function convertAmount(
        address fromToken,
        address toToken,
        uint256 amount
    ) external view returns (uint256 convertedAmount);

    /// @notice Check if a token pair is supported
    /// @param token Token to check
    /// @param baseToken Base token to check against
    /// @return supported True if the pair is supported
    function isPairSupported(address token, address baseToken) external view returns (bool supported);
}
