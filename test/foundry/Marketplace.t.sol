// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {Marketplace} from "contracts/modules/marketplace/Marketplace.sol";
import {MockRegistry} from "contracts/mocks/MockRegistry.sol";
import {MockAccessControlCenter} from "contracts/mocks/MockAccessControlCenter.sol";
import {MockPaymentGateway} from "contracts/mocks/MockPaymentGateway.sol";
import {TestToken} from "contracts/mocks/TestToken.sol";

contract MarketplaceTest is Test {
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
        bytes32 moduleId = keccak256("Market");
        market = new Marketplace(address(registry), address(gateway), moduleId);
        token.transfer(buyer, 100 ether);
    }

    function testListAndBuy() public {
        uint256 price = 1 ether;
        vm.prank(seller);
        vm.expectEmit(true, true, false, true);
        emit Marketplace.MarketplaceListingCreated(0, seller, address(token), price);
        uint256 id = market.list(address(token), price);
        (address sellerAddr, address tkn, uint256 pr, bool active) = market.listings(id);
        assertEq(sellerAddr, seller);
        assertEq(tkn, address(token));
        assertEq(pr, price);
        assertTrue(active);

        vm.prank(buyer);
        token.approve(address(gateway), price);
        vm.prank(buyer);
        vm.expectEmit(true, true, false, true);
        emit Marketplace.MarketplaceListingSold(id, buyer);
        market.buy(id);

        assertEq(token.balanceOf(seller), price);
        assertEq(token.balanceOf(buyer), 99 ether);
        (, , , active) = market.listings(id);
        assertFalse(active);
    }
}

