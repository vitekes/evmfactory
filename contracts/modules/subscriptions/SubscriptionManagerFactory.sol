// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../../shared/BaseFactory.sol';
import './SubscriptionManager.sol';
import '../../interfaces/CoreDefs.sol';
import '../../interfaces/IGateway.sol';

 /// @title SubscriptionManagerFactory
 /// @notice Factory for creating subscription manager instances
 /// @dev Uses PaymentGateway (IGateway) for payment processing
contract SubscriptionManagerFactory is BaseFactory {
    event SubscriptionManagerCreated(address indexed creator, address subManager);

    constructor(
        address registry,
        address paymentGateway
    ) BaseFactory(registry, paymentGateway, CoreDefs.SUBSCRIPTION_MODULE_ID) {}

             /// @notice Creates a new subscription manager instance
             /// @return m Address of the created subscription manager
    function createSubscriptionManager() external onlyFactoryAdmin nonReentrant returns (address m) {
        // Cache addresses to reduce storage reads
        address gateway = paymentGateway;
        address registryAddr = address(registry);
        address sender = msg.sender;

        // Check gateway (required check)
        if (gateway == address(0)) revert PaymentGatewayNotRegistered();

        // Generate ID before external calls
        bytes32 instanceId = _generateInstanceId('SubscriptionManager');

        // Batch initialization in registry
        registry.registerFeature(instanceId, address(this), 1);

        // Optimized service copying with minimal external calls
        // Copy services in batch, combining operations
        {
            // Use block to limit scope of temporary variables
            registry.setModuleServiceAlias(instanceId, 'PaymentGateway', gateway);

            // Cache services and copy them only if they exist
            address validator = registry.getModuleServiceByAlias(CoreDefs.SUBSCRIPTION_MODULE_ID, 'Validator');
            if (validator != address(0)) {
                registry.setModuleServiceAlias(instanceId, 'Validator', validator);
            }

            address oracle = registry.getModuleServiceByAlias(CoreDefs.SUBSCRIPTION_MODULE_ID, 'PriceOracle');
            if (oracle != address(0)) {
                registry.setModuleServiceAlias(instanceId, 'PriceOracle', oracle);
            }
        }

        // Create subscription manager using cached addresses
        m = address(new SubscriptionManager(registryAddr, gateway, instanceId));

        // Update instance address in registry
        registry.upgradeFeature(instanceId, m);

        emit SubscriptionManagerCreated(sender, m);
    }
}
