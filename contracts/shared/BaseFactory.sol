// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../interfaces/ICoreKernel.sol';
import '../errors/Errors.sol';
import './CloneFactory.sol';
import '../interfaces/CoreDefs.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import '../interfaces/IGateway.sol';

abstract contract BaseFactory is CloneFactory, ReentrancyGuard {
    ICoreKernel public immutable registry;
    address public immutable paymentGateway;
    bytes32 public immutable MODULE_ID;

    bytes32 public constant FACTORY_ADMIN = keccak256('FACTORY_ADMIN');

    constructor(address _registry, address _paymentGateway, bytes32 moduleId) {
        if (_registry == address(0)) revert ZeroAddress();
        if (_paymentGateway == address(0)) revert ZeroAddress();
        if (moduleId == bytes32(0)) revert InvalidAddress();

        registry = ICoreKernel(_registry);
        paymentGateway = _paymentGateway;
        MODULE_ID = moduleId;

        // Check if module is registered in registry
        // If not, services will be linked later outside the constructor
        try registry.getFeature(moduleId) returns (address, uint8) {
            // If module is registered, register payment gateway
            bool success = false;
            try registry.setModuleServiceAlias(moduleId, 'PaymentGateway', _paymentGateway) {
                success = true;
            } catch Error(string memory /* reason */) {
                // In real contract we could add logging via event
                // emit RegistryError(reason);
            }
        } catch Error(string memory /* reason */) {
            // In real contract we could add logging via event
            // emit FeatureNotFound(reason);
        } catch {
            // Handle other exceptions
            // emit UnknownRegistryError();
        }
    }

    // Constant for ACL service identifier
    bytes32 private constant ACL_SERVICE = CoreDefs.SERVICE_ACCESS_CONTROL;

    modifier onlyFactoryAdmin() {
        ICoreKernel acl = ICoreKernel(registry.getCoreService(ACL_SERVICE));
        if (!acl.hasRole(FACTORY_ADMIN, msg.sender)) revert NotFactoryAdmin();
        _;
    }

    /// @dev Copies service from main module to instance if service exists
    /// @param instanceId Instance ID
    /// @param serviceName Service name
    /// @return Address of copied service or address(0) if service doesn't exist
    function _copyServiceIfExists(bytes32 instanceId, string memory serviceName) internal returns (address) {
        // Check input parameters validity
        if (instanceId == bytes32(0)) revert InvalidAddress();
        if (bytes(serviceName).length == 0) revert InvalidServiceName();

        // Get service and immediately check for 0
        address service = registry.getModuleServiceByAlias(MODULE_ID, serviceName);
        if (service != address(0)) {
            // Call registry only when actually needed
            registry.setModuleServiceAlias(instanceId, serviceName, service);
        }
        return service;
    }

    // Counter for additional entropy
    uint256 private _instanceCounter;

    /// @dev Creates a unique identifier for a new module instance
    /// @param prefix Prefix for identifier (e.g., module name)
    /// @return Unique identifier for the module instance

    function _generateInstanceId(string memory prefix) internal returns (bytes32) {
        // Increment counter for additional entropy
        _instanceCounter++;

        // Optimized version with enhanced entropy
        return
            keccak256(
                abi.encodePacked(
                    bytes32(bytes(prefix)), // Fixed size 32 bytes saves gas
                    uint160(address(this)), // Directly use uint160
                    block.timestamp,
                    block.prevrandao,
                    _instanceCounter, // Add incrementing counter
                    blockhash(block.number - 1) // Use previous block hash for additional entropy
                )
            );
    }
}
