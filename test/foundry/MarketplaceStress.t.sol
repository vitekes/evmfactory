// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {Marketplace} from "contracts/modules/marketplace/Marketplace.sol";
import {MockRegistry} from "contracts/mocks/MockRegistry.sol";
import {MockAccessControlCenter} from "contracts/mocks/MockAccessControlCenter.sol";
import {MockPaymentGateway} from "contracts/mocks/MockPaymentGateway.sol";
import {TestToken} from "contracts/mocks/TestToken.sol";

contract MarketplaceStressTest is Test {
    Marketplace internal market;
    MockRegistry internal registry;
    MockAccessControlCenter internal acc;
    MockPaymentGateway internal gateway;
    TestToken internal token;

    address internal seller = address(0x1);
    address internal buyer = address(0x2);

    function setUp() public {
        token = new TestToken("T", "T");
        registry = new MockRegistry();
        acc = new MockAccessControlCenter();
        registry.setCoreService(keccak256("AccessControlCenter"), address(acc));
        gateway = new MockPaymentGateway();
        bytes32 moduleId = keccak256("MarketStress");
        registry.setModuleServiceAlias(moduleId, "PaymentGateway", address(gateway));
        market = new Marketplace(address(registry), address(gateway), moduleId);
        token.transfer(buyer, 1000 ether);
    }

    function testStressListAndBuy() public {
        uint256 count = 50;
        uint256 price = 1 ether;
        for (uint256 i; i < count; ++i) {
            vm.prank(seller);
            market.list(address(token), price);
        }

        vm.startPrank(buyer);
        token.approve(address(gateway), price * count);
        for (uint256 i; i < count; ++i) {
            market.buy(i);
            (, , , bool active) = market.listings(i);
            assertFalse(active);
        }
        vm.stopPrank();

        assertEq(token.balanceOf(seller), price * count);
        assertEq(token.balanceOf(buyer), 1000 ether - price * count);
    }
}

