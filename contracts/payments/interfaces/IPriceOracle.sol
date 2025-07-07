// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IPriceOracle {
    /// @notice Convert amount from one token to another
    /// @param baseToken Base token address
    /// @param quoteToken Quote token address
    /// @param amount Amount to convert
    /// @return The amount in quote token
    function convertAmount(address baseToken, address quoteToken, uint256 amount) external view returns (uint256);

    /// @notice Check if pair is supported by oracle
    /// @param baseToken Base token address
    /// @param quoteToken Quote token address
    /// @return supported Whether the pair is supported
    function isPairSupported(address baseToken, address quoteToken) external view returns (bool);
}