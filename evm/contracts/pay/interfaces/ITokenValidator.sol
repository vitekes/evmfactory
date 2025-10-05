// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title ITokenValidator
/// @notice Minimal interface for token validation
interface ITokenValidator {
    /// @notice Check whether the token is allowed
    /// @param token Address of the token to validate
    /// @return allowed True if the token can be used
    function isTokenAllowed(address token) external view returns (bool allowed);
}
