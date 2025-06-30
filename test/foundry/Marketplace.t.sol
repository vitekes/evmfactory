// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {Marketplace} from "contracts/modules/marketplace/Marketplace.sol";
import {MockRegistry} from "contracts/mocks/MockRegistry.sol";
import {MockAccessControlCenter} from "contracts/mocks/MockAccessControlCenter.sol";
import {MockPaymentGateway} from "contracts/mocks/MockPaymentGateway.sol";
import {TestToken} from "contracts/mocks/TestToken.sol";
import {SignatureLib} from "contracts/lib/SignatureLib.sol";
import {InvalidChain} from "contracts/errors/Errors.sol";

contract MarketplaceTest is Test {
    Marketplace internal market;
    MockRegistry internal registry;
    MockAccessControlCenter internal acc;
    MockPaymentGateway internal gateway;
    TestToken internal token;

    address internal seller;
    uint256 internal sellerPk = 1;
    address internal buyer = address(0x2);

    function setUp() public {
        seller = vm.addr(sellerPk);
        token = new TestToken("T", "T");
        registry = new MockRegistry();
        acc = new MockAccessControlCenter();
        registry.setCoreService(keccak256("AccessControlCenter"), address(acc));
        gateway = new MockPaymentGateway();
        bytes32 moduleId = keccak256("Market");
        registry.setModuleServiceAlias(moduleId, "PaymentGateway", address(gateway));
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

    function _listing(bytes32 sku) internal view returns (SignatureLib.Listing memory l) {
        l = SignatureLib.Listing({
            chainIds: new uint256[](1),
            token: address(token),
            price: 2 ether,
            sku: sku,
            seller: seller,
            salt: 1,
            expiry: uint64(block.timestamp + 1 days)
        });
        l.chainIds[0] = block.chainid;
    }

    function _sign(bytes32 digest, uint256 pk) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function testUpdateListingPrice() public {
        uint256 price = 1 ether;
        vm.prank(seller);
        uint256 id = market.list(address(token), price);
        vm.prank(seller);
        vm.expectEmit(true, false, false, true);
        bytes32 hash = keccak256(abi.encodePacked(id, seller, address(token)));
        emit Marketplace.ListingUpdated(hash, price, price * 2);
        market.updateListingPrice(id, price * 2);
        (, , uint256 p, ) = market.listings(id);
        assertEq(p, price * 2);
    }

    function testSignaturePurchase() public {
        bytes32 sku = keccak256("SKU1");
        SignatureLib.Listing memory l = _listing(sku);
        bytes32 h = market.hashListing(l);
        bytes memory sig = _sign(h, 0x1);
        token.transfer(buyer, 2 ether);
        vm.prank(buyer);
        token.approve(address(gateway), l.price);
        vm.prank(buyer);
        vm.expectEmit(true, true, false, true);
        emit Marketplace.MarketplaceListingPurchased(buyer, h, block.chainid);
        market.buy(l, sig);
        assertEq(token.balanceOf(seller), l.price);
        assertTrue(market.consumed(h, buyer));
    }

    function testInvalidChainReverts() public {
        SignatureLib.Listing memory l = _listing(keccak256("SKU2"));
        l.chainIds[0] = block.chainid + 1;
        bytes32 h = market.hashListing(l);
        bytes memory sig = _sign(h, 0x1);
        vm.prank(buyer);
        token.approve(address(gateway), l.price);
        vm.prank(buyer);
        vm.expectRevert(InvalidChain.selector);
        market.buy(l, sig);
    }
}
