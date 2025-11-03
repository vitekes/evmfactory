// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../../core/BaseFactory.sol';
import '../../core/CoreDefs.sol';
import './Donate.sol';

/// @title DonateFactory
/// @notice Factory for deploying Donate module instances
contract DonateFactory is BaseFactory {
    event DonateModuleCreated(address indexed creator, address donateModule);

    constructor(address coreSystem, address paymentGateway)
        BaseFactory(coreSystem, paymentGateway, CoreDefs.DONATE_MODULE_ID)
    {}

    function createDonateModule() external onlyFactoryAdmin nonReentrant returns (address module) {
        bytes32 instanceId = _generateInstanceId('Donate');

        core.registerFeature(instanceId, address(this), 1);
        core.setService(instanceId, 'PaymentGateway', paymentGateway);

        module = address(new Donate(address(core), paymentGateway, instanceId));

        core.upgradeFeature(instanceId, module);

        emit DonateModuleCreated(msg.sender, module);
    }
}
