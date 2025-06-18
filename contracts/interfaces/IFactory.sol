// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IFactory
/// @notice Generic interface for module factories
interface IFactory {
    /// Emitted when a new module instance is deployed
    event ModuleDeployed(address indexed creator, address module);

    /// Deploy a new module instance using encoded parameters
    function deploy(bytes calldata data) external returns (address module);
}
