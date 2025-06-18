// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IPriceFeed
/// @notice Returns token price denominated in USD with 18 decimals
interface IPriceFeed {
    function tokenPriceUsd(address token) external view returns (uint256);
}
