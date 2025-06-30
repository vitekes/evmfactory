// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {MarketplaceFactory} from "contracts/modules/marketplace/MarketplaceFactory.sol";
import {MockRegistry} from "contracts/mocks/MockRegistry.sol";
import {MockPaymentGateway} from "contracts/mocks/MockPaymentGateway.sol";
import {AccessControlCenter} from "contracts/core/AccessControlCenter.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PaymentGatewayNotRegistered, NotFactoryAdmin} from "contracts/errors/Errors.sol";

contract MarketplaceFactoryTest is Test {
    MarketplaceFactory internal factory;
    MockRegistry internal registry;
    MockPaymentGateway internal gateway;
    AccessControlCenter internal acc;

    bytes32 internal constant FACTORY_ADMIN = keccak256("FACTORY_ADMIN");
    bytes32 internal constant MODULE_ID = keccak256("Marketplace");

    function setUp() public {
        registry = new MockRegistry();
        gateway = new MockPaymentGateway();
        AccessControlCenter accImpl = new AccessControlCenter();
        bytes memory accData = abi.encodeCall(AccessControlCenter.initialize, address(this));
        ERC1967Proxy accProxy = new ERC1967Proxy(address(accImpl), accData);
        acc = AccessControlCenter(address(accProxy));
        acc.grantRole(FACTORY_ADMIN, address(this));
        registry.setCoreService(keccak256("AccessControlCenter"), address(acc));
        factory = new MarketplaceFactory(address(registry), address(gateway));
    }

    function testCreateMarketplaceRegistersAndReturnsAddress() public {
        registry.setModuleServiceAlias(MODULE_ID, "PaymentGateway", address(gateway));
        uint256 ts = 1234;
        vm.warp(ts);
        bytes32 id = keccak256(abi.encodePacked("Marketplace:", address(factory), ts));
        address m = factory.createMarketplace();
        assertEq(registry.features(id), m);
        assertEq(registry.getModuleServiceByAlias(id, "PaymentGateway"), address(gateway));
    }

    function testCreateMarketplaceNoGateway() public {
        vm.expectRevert(PaymentGatewayNotRegistered.selector);
        factory.createMarketplace();
    }

    function testOnlyFactoryAdmin() public {
        registry.setModuleServiceAlias(MODULE_ID, "PaymentGateway", address(gateway));
        address other = address(0x1);
        vm.prank(other);
        vm.expectRevert(NotFactoryAdmin.selector);
        factory.createMarketplace();
    }
}
