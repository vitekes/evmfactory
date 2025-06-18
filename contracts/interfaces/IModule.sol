// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IModule
/// @notice Base interface for feature modules
interface IModule {
    /// @dev Unique module identifier used for Registry lookups
    function MODULE_ID() external view returns (bytes32);

    /// @notice Optional callback invoked after a payment is processed
    function onPayment(address token, uint256 amount, bytes calldata data) external;
}
