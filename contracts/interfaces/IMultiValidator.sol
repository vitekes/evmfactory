// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IMultiValidator
/// @notice Interface for token validator with full set of methods
/// @dev Contains methods for checking and managing the list of allowed tokens
interface IMultiValidator {
    /// @notice Initializes the validator
    /// @param acl Address of the access control contract
    function initialize(address acl) external;

    /// @notice Sets token status (allowed/disallowed)
    /// @param token Token address
    /// @param allowed Permission status
    function setToken(address token, bool allowed) external;

    /// @notice Adds token to the allowed list
    /// @param token Token address
    function addToken(address token) external;

    /// @notice Removes token from the allowed list
    /// @param token Token address
    function removeToken(address token) external;

    /// @notice Bulk status setting for multiple tokens
    /// @param tokens Array of token addresses
    /// @param allowed Permission status
    function bulkSetToken(address[] calldata tokens, bool allowed) external;

    /// @notice Checks if a token is allowed
    /// @param token Token address to check
    /// @return allowed true if token is allowed
    function isAllowed(address token) external view returns (bool);

    /// @notice Checks if all tokens from the array are allowed
    /// @param tokens Array of token addresses to check
    /// @return allowed true if all tokens are allowed
    function areAllowed(address[] calldata tokens) external view returns (bool);

    /// @notice Sets new access control contract
    /// @param newAccess Address of the new contract
    function setAccessControl(address newAccess) external;
}
