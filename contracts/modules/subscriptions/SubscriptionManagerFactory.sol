// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../../shared/BaseFactory.sol';
import './SubscriptionManager.sol';
import '../../shared/CoreDefs.sol';
import '../../payments/interfaces/IGateway.sol';
import '../../core/interfaces/ICoreSystem.sol';

/// @title SubscriptionManagerFactory
/// @notice Factory for creating subscription manager instances
/// @dev Uses PaymentGateway (IGateway) for payment processing
contract SubscriptionManagerFactory is BaseFactory {
    event SubscriptionManagerCreated(address indexed creator, address subManager);

    constructor(
        address coreSystem,
        address paymentGateway
    ) BaseFactory(coreSystem, paymentGateway, CoreDefs.SUBSCRIPTION_MODULE_ID) {}

    /// @notice Creates a new subscription manager instance
    /// @return m Address of the created subscription manager
    function createSubscriptionManager() external onlyFactoryAdmin nonReentrant returns (address m) {
        // Cache addresses to reduce storage reads
        address gateway = paymentGateway;
        address coreAddr = address(core);
        address sender = msg.sender;

        // Check gateway (required check)
        if (gateway == address(0)) revert PaymentGatewayNotRegistered();

        // Generate ID before external calls
        bytes32 instanceId = _generateInstanceId('SubscriptionManager');

        // Batch initialization in core
        core.registerFeature(instanceId, address(this), 1);

        // Optimized service copying with minimal external calls
        // Copy services in batch, combining operations
        {
            // Use block to limit scope of temporary variables
            core.setModuleServiceAlias(instanceId, 'PaymentGateway', gateway);

            // Cache services and copy them only if they exist
            address validator = core.getModuleServiceByAlias(CoreDefs.SUBSCRIPTION_MODULE_ID, 'Validator');
            if (validator != address(0)) {
                core.setModuleServiceAlias(instanceId, 'Validator', validator);
            }

            address oracle = core.getModuleServiceByAlias(CoreDefs.SUBSCRIPTION_MODULE_ID, 'PriceOracle');
            if (oracle != address(0)) {
                core.setModuleServiceAlias(instanceId, 'PriceOracle', oracle);
            }
        }

        // Create subscription manager using cached addresses
        m = address(new SubscriptionManager(coreAddr, gateway, instanceId));

        // Update instance address in core
        core.upgradeFeature(instanceId, m);

        emit SubscriptionManagerCreated(sender, m);
    }
}
