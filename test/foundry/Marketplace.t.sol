// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {MockRegistry} from "contracts/mocks/MockRegistry.sol";
import {AccessControlCenter} from "contracts/core/AccessControlCenter.sol";
import {MockPaymentGateway} from "contracts/mocks/MockPaymentGateway.sol";
import {MultiValidator} from "contracts/core/MultiValidator.sol";
import {TestToken} from "contracts/mocks/TestToken.sol";
import {SignatureLib} from "contracts/lib/SignatureLib.sol";
import {TestHelper} from "./TestHelper.sol";
import { MarketplaceForTest } from "./MarketplaceForTest.sol";


contract MarketplaceTest is Test {
    MarketplaceForTest public market;
    MockRegistry public registry;
    AccessControlCenter public acl;
    MockPaymentGateway public gateway;
    MultiValidator public validator;
    TestToken public token;

    uint256 public sellerPk = 1;
    uint256 public buyerPk = 2;
    address public seller;
    address public buyer;

    bytes32 public constant MODULE_ID = keccak256("Market");

    function setUp() public {
        seller = vm.addr(sellerPk);
        buyer = vm.addr(buyerPk);

        vm.startPrank(address(this));
        acl = new AccessControlCenter();
        acl.initialize(address(this));

        registry = new MockRegistry();
        registry.setCoreService(keccak256(bytes("AccessControlCenter")), address(acl));
        gateway = new MockPaymentGateway();
        registry.setModuleServiceAlias(MODULE_ID, "PaymentGateway", address(gateway));

        market = new MarketplaceForTest(
            address(registry),
            address(gateway),
            MODULE_ID
        );
        validator = new MultiValidator();
        acl.grantRole(acl.DEFAULT_ADMIN_ROLE(), address(validator));
        validator.initialize(address(acl));
        registry.setModuleServiceAlias(MODULE_ID, "Validator", address(validator));
        acl.grantRole(acl.FEATURE_OWNER_ROLE(), address(gateway));
        TestHelper.grantRolesForModule(
            acl,
            address(market),
            address(validator),
            address(0)
        );

        address[] memory gov;
        address[] memory fo = new address[](2);
        fo[0] = address(this);
        fo[1] = address(market);
        address[] memory mods = new address[](1);
        mods[0] = address(market);
        TestHelper.setupAclAndRoles(acl, gov, fo, mods);
        vm.stopPrank();

        token = new TestToken("Test", "TST");
        token.transfer(seller, 100 ether);
        token.transfer(buyer, 100 ether);

        vm.prank(buyer);
        token.approve(address(gateway), type(uint256).max);
    }

    function _listing() internal view returns (SignatureLib.Listing memory l) {
        uint256[] memory chains = new uint256[](1);
        chains[0] = block.chainid;
        l = SignatureLib.Listing({
            chainIds: chains,
            token: address(token),
            price: 1 ether,
            sku: bytes32("1"),
            seller: seller,
            salt: 1,
            expiry: 0
        });
    }

    function testLazyBuy() public {
        SignatureLib.Listing memory l = _listing();
        bytes32 hash = market.hashListing(l);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, hash);
        bytes memory sig = abi.encodePacked(r, s, v);

        uint256 beforeBal = token.balanceOf(seller);
        vm.prank(buyer);
        market.buy(l, sig);
        assertEq(token.balanceOf(seller), beforeBal + 1 ether);
        assertTrue(market.consumed(hash, buyer));
    }

    function testLazyBuyTampered() public {
        SignatureLib.Listing memory l = _listing();
        bytes32 hash = market.hashListing(l);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, hash);
        bytes memory sig = abi.encodePacked(r, s, v);

        l.price = 2 ether;
        vm.prank(buyer);
        vm.expectRevert("InvalidSignature()");
        market.buy(l, sig);
    }

    function testOnchainListingPurchase() public {
        vm.prank(seller);
        uint256 id = market.list(address(token), 1 ether);

        uint256 beforeSeller = token.balanceOf(seller);
        uint256 beforeBuyer = token.balanceOf(buyer);

        vm.prank(buyer);
        market.buy(id);

        assertEq(token.balanceOf(seller), beforeSeller + 1 ether);
        assertEq(token.balanceOf(buyer), beforeBuyer - 1 ether);
        (, , , bool active) = market.listings(id);
        assertFalse(active);
    }

    function testUpdateListingNotSeller() public {
        vm.prank(seller);
        uint256 id = market.list(address(token), 1 ether);

        vm.prank(buyer);
        vm.expectRevert("NotSeller()");
        market.updateListingPrice(id, 2 ether);
    }

    function testBuyInactiveListing() public {
        vm.prank(seller);
        uint256 id = market.list(address(token), 1 ether);

        vm.prank(buyer);
        market.buy(id);

        vm.prank(buyer);
        vm.expectRevert("NotListed()");
        market.buy(id);
    }

    function testLazyBuyWrongChain() public {
        SignatureLib.Listing memory l = _listing();
        l.chainIds[0] = block.chainid + 1;
        bytes32 hash = market.hashListing(l);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, hash);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.prank(buyer);
        vm.expectRevert("InvalidChain()");
        market.buy(l, sig);
    }

    function testLazyBuyExpired() public {
        SignatureLib.Listing memory l = _listing();
        l.expiry = uint64(block.timestamp + 1);
        bytes32 hash = market.hashListing(l);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, hash);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.warp(block.timestamp + 2);

        vm.prank(buyer);
        vm.expectRevert("Expired()");
        market.buy(l, sig);
    }
}
