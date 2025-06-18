// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../shared/BaseFactory.sol";
import "./Marketplace.sol";

contract MarketplaceFactory is BaseFactory {
    event MarketplaceCreated(address indexed creator, address marketplace);

    constructor(address registry, address paymentGateway)
        BaseFactory(registry, paymentGateway, keccak256("Marketplace"))
    {}

    function createMarketplace() external onlyFactoryAdmin nonReentrant returns (address m) {
        address gateway = registry.getModuleService(MODULE_ID, keccak256(bytes("PaymentGateway")));
        m = address(new Marketplace(address(registry), gateway, MODULE_ID));
        registry.registerFeature(keccak256(abi.encodePacked("Marketplace:", m)), m, 1);
        emit MarketplaceCreated(msg.sender, m);
    }
}
