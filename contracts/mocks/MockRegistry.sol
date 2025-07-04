// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../interfaces/IRegistry.sol';

/// @title MockRegistry
/// @notice Test registry for modular testing
/// @dev Used only for testing, not for production use
contract MockRegistry is IRegistry {
    // Mapping of modules by ID
    mapping(bytes32 => address) public modules;
    mapping(bytes32 => uint8) public moduleContexts;

    // Mapping of core services (by bytes32)
    mapping(bytes32 => address) public coreSrvByBytes;

    // Mapping of module services (by bytes32)
    mapping(bytes32 => mapping(bytes32 => address)) public moduleSrvByBytes;

    // Mapping of module services (by string)
    mapping(bytes32 => mapping(string => address)) public moduleServices;

    // Access control system address
    address public accessControl;

    // Owner address for basic access control
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    // Basic access control modifier for testing
    modifier onlyOwner() {
        require(msg.sender == owner, 'Not owner');
        _;
    }

    /// @notice Registers a new module
    /// @param id Module ID
    /// @param implementation Implementation address
    /// @param context Module context
    function registerFeature(bytes32 id, address implementation, uint8 context) external onlyOwner {
        require(id != bytes32(0), 'Invalid module ID');
        require(implementation != address(0), 'Zero address not allowed');
        modules[id] = implementation;
        moduleContexts[id] = context;
    }

    /// @notice Updates module address
    /// @param id Module ID
    /// @param newImplementation New implementation address
    function upgradeFeature(bytes32 id, address newImplementation) external onlyOwner {
        require(id != bytes32(0), 'Invalid module ID');
        require(newImplementation != address(0), 'Zero address not allowed');
        modules[id] = newImplementation;
    }

    /// @notice Gets module information
    /// @param id Module ID
    /// @return implementation Implementation address
    /// @return context Module context
    function getFeature(bytes32 id) external view returns (address implementation, uint8 context) {
        return (modules[id], moduleContexts[id]);
    }

    /// @notice Gets module context
    /// @param id Module ID
    /// @return Module context
    function getContext(bytes32 id) external view returns (uint8) {
        return moduleContexts[id];
    }

    /// @notice Registers a core service (by bytes32)
    /// @param serviceId Service ID
    /// @param addr Service address
    function setCoreService(bytes32 serviceId, address addr) external onlyOwner {
        require(serviceId != bytes32(0), 'Invalid service ID');
        require(addr != address(0), 'Zero address not allowed');
        coreSrvByBytes[serviceId] = addr;
    }

    /// @notice Gets core service address (by bytes32)
    /// @param serviceId Service ID
    /// @return Service address
    function getCoreService(bytes32 serviceId) external view returns (address) {
        return coreSrvByBytes[serviceId];
    }

    /// @notice Registers a module service (by bytes32)
    /// @param moduleId Module ID
    /// @param serviceId Service ID
    /// @param addr Service address
    function setModuleService(bytes32 moduleId, bytes32 serviceId, address addr) external onlyOwner {
        moduleSrvByBytes[moduleId][serviceId] = addr;
    }

    /// @notice Gets module service address (by bytes32)
    /// @param moduleId Module ID
    /// @param serviceId Service ID
    /// @return Service address
    function getModuleService(bytes32 moduleId, bytes32 serviceId) external view returns (address) {
        return moduleSrvByBytes[moduleId][serviceId];
    }

    /// @notice Registers a module service (by string)
    /// @param moduleId Module ID
    /// @param serviceAlias Service name
    /// @param addr Service address
    function setModuleServiceAlias(bytes32 moduleId, string calldata serviceAlias, address addr) external onlyOwner {
        require(moduleId != bytes32(0), 'Invalid module ID');
        require(bytes(serviceAlias).length > 0, 'Empty service alias');
        require(addr != address(0), 'Zero address not allowed');

        moduleServices[moduleId][serviceAlias] = addr;
        bytes32 serviceId = keccak256(bytes(serviceAlias));
        require(serviceId != bytes32(0), 'Invalid service ID');
        moduleSrvByBytes[moduleId][serviceId] = addr;
    }

    /// @notice Gets module service address (by string)
    /// @param moduleId Module ID
    /// @param serviceAlias Service name
    /// @return Service address
    function getModuleServiceByAlias(bytes32 moduleId, string calldata serviceAlias) external view returns (address) {
        return moduleServices[moduleId][serviceAlias];
    }

    /// @notice Gets module service address (compatibility with previous API)
    /// @param moduleId Module ID
    /// @param serviceAlias Service name
    /// @return Service address
    function getModuleService(bytes32 moduleId, string calldata serviceAlias) external view returns (address) {
        return moduleServices[moduleId][serviceAlias];
    }

    /// @notice Sets new access control contract
    /// @param newAccess New contract address
    function setAccessControl(address newAccess) external onlyOwner {
        require(newAccess != address(0), 'Zero address not allowed');
        accessControl = newAccess;
    }

    /// @notice Checks if module exists (helper function)
    /// @param id Module ID
    /// @return Whether module exists
    function featureExists(bytes32 id) external view returns (bool) {
        return modules[id] != address(0);
    }
}
