// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IValidator
/// @notice Minimal interface for token validators
interface IValidator {
    function isAllowed(address token) external view returns (bool);
}
