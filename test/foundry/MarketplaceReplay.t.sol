// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {MockRegistry} from "contracts/mocks/MockRegistry.sol";
import {MockPaymentGateway} from "contracts/mocks/MockPaymentGateway.sol";
import {TestToken} from "contracts/mocks/TestToken.sol";
import {SignatureLib} from "contracts/lib/SignatureLib.sol";
import {Marketplace} from "contracts/modules/marketplace/Marketplace.sol";
import {MockAccessControlCenter} from "contracts/mocks/MockAccessControlCenter.sol";

contract MarketplaceReplayTest is Test {
    MockRegistry registry;
    MockPaymentGateway gateway;
    Marketplace public market;
    TestToken token;

    uint256 sellerPk = 1;
    uint256 buyerPk = 2;
    address seller;
    address buyer;

    bytes32 constant MODULE_ID = keccak256("Market");

    function setUp() public {
        seller = vm.addr(sellerPk);
        buyer = vm.addr(buyerPk);

        registry = new MockRegistry();
        MockAccessControlCenter acl = new MockAccessControlCenter();
        registry.setCoreService(keccak256(bytes("AccessControlCenter")), address(acl));

        gateway = new MockPaymentGateway();
        registry.setModuleServiceAlias(MODULE_ID, "PaymentGateway", address(gateway));

        market = new Marketplace(address(registry), address(gateway), MODULE_ID);

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

    function testLazyBuyReplay() public {
        SignatureLib.Listing memory l = _listing();
        bytes32 hash = market.hashListing(l);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, hash);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.prank(buyer);
        market.buy(l, sig);

        vm.prank(buyer);
        vm.expectRevert("AlreadyPurchased()");
        market.buy(l, sig);
    }
}
