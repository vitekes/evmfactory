// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title Native
/// @notice Utility library for native currency handling
/// @dev Helps identify native currency addresses across different implementations
library Native {
    /// @notice ETH sentinel address used by many protocols
    address internal constant ETH_SENTINEL = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice Zero address is also used to represent native currency
    address internal constant ZERO_ADDRESS = address(0);

    /// @notice Checks if the token address represents a native currency
    /// @param token Token address to check
    /// @return true if token is native currency, false otherwise
    function isNative(address token) internal pure returns (bool) {
        return token == ZERO_ADDRESS || token == ETH_SENTINEL;
    }
}
