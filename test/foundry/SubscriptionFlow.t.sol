// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {SubscriptionManager} from "contracts/modules/subscriptions/SubscriptionManager.sol";
import {MockRegistry} from "contracts/mocks/MockRegistry.sol";
import {AccessControlCenter} from "contracts/core/AccessControlCenter.sol";
import {MockPaymentGateway} from "contracts/mocks/MockPaymentGateway.sol";
import {TestToken} from "contracts/mocks/TestToken.sol";
import {SignatureLib} from "contracts/lib/SignatureLib.sol";
import {TestHelper} from "./TestHelper.sol";

contract SubscriptionFlowTest is Test {
    MockRegistry registry;
    AccessControlCenter acc;
    MockPaymentGateway gateway;
    SubscriptionManager manager;
    TestToken token;

    uint256 userPk = 1;
    uint256 merchantPk = 2;
    address user;
    address merchant;

    bytes32 constant MODULE_ID = keccak256("Sub");

    function setUp() public {
        user = vm.addr(userPk);
        merchant = vm.addr(merchantPk);

        acc = new AccessControlCenter();
        acc.initialize(address(this));
        vm.startPrank(address(this));

        registry = new MockRegistry();
        registry.setCoreService(keccak256(bytes("AccessControlCenter")), address(acc));
        gateway = new MockPaymentGateway();
        registry.setModuleServiceAlias(MODULE_ID, "PaymentGateway", address(gateway));

        manager = new SubscriptionManager(address(registry), address(gateway), MODULE_ID);

        acc.grantRole(acc.FEATURE_OWNER_ROLE(), address(gateway));
        acc.grantRole(acc.AUTOMATION_ROLE(), address(manager));

        address[] memory gov;
        address[] memory fo = new address[](2);
        fo[0] = address(this);
        fo[1] = address(manager);
        address[] memory mods = new address[](1);
        mods[0] = address(manager);
        TestHelper.setupAclAndRoles(acc, gov, fo, mods);

        vm.stopPrank();

        token = new TestToken("Test", "TST");
        token.transfer(user, 10 ether);

        vm.prank(user);
        token.approve(address(gateway), type(uint256).max);
    }

    function _plan() internal view returns (SignatureLib.Plan memory p) {
        uint256[] memory chains = new uint256[](1);
        chains[0] = block.chainid;
        p = SignatureLib.Plan({
            chainIds: chains,
            price: 1 ether,
            period: 100,
            token: address(token),
            merchant: merchant,
            salt: 1,
            expiry: 0
        });
    }

    function _merchantSig(SignatureLib.Plan memory p) internal returns (bytes memory) {
        bytes32 ph = manager.hashPlan(p);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(merchantPk, ph);
        return abi.encodePacked(r, s, v);
    }

    function testUnsubscribeClearsRecord() public {
        SignatureLib.Plan memory p = _plan();
        bytes memory sigMerchant = _merchantSig(p);

        vm.prank(user);
        manager.subscribe(p, sigMerchant, "");

        vm.warp(block.timestamp + 1);
        uint256 ts = block.timestamp;
        bytes32 ph = manager.hashPlan(p);

        vm.expectEmit(true, true, false, true);
        emit SubscriptionManager.Unsubscribed(user, ph);
        vm.expectEmit(true, true, false, true);
        emit SubscriptionManager.PlanCancelled(user, ph, ts);

        vm.prank(user);
        manager.unsubscribe();

        (uint256 nextBilling, bytes32 planHash) = manager.subscribers(user);
        assertEq(nextBilling, 0);
        assertEq(planHash, bytes32(0));
    }
}
