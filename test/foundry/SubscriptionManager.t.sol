// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {SubscriptionManager} from "contracts/modules/subscriptions/SubscriptionManager.sol";
import {MockRegistry} from "contracts/mocks/MockRegistry.sol";
import {MockAccessControlCenterAuto} from "contracts/mocks/MockAccessControlCenterAuto.sol";
import {MockPaymentGateway} from "contracts/mocks/MockPaymentGateway.sol";
import {TestToken} from "contracts/mocks/TestToken.sol";
import {SignatureLib} from "contracts/lib/SignatureLib.sol";

contract SubscriptionManagerTest is Test {
    SubscriptionManager internal sub;
    MockRegistry internal registry;
    MockAccessControlCenterAuto internal acc;
    MockPaymentGateway internal gateway;
    TestToken internal token;

    address internal merchant;
    uint256 internal merchantPk = 1;
    address internal user = address(0xBEEF);
    address internal keeper = address(0xCAFE);

    function setUp() public {
        merchant = vm.addr(merchantPk);
        token = new TestToken("T", "T");
        registry = new MockRegistry();
        acc = new MockAccessControlCenterAuto();
        registry.setCoreService(keccak256("AccessControlCenter"), address(acc));
        gateway = new MockPaymentGateway();
        bytes32 moduleId = keccak256("Sub");
        registry.setModuleServiceAlias(moduleId, "PaymentGateway", address(gateway));
        sub = new SubscriptionManager(address(registry), address(gateway), moduleId);
        token.transfer(user, 10 ether);
    }

    function _defaultPlan() internal view returns (SignatureLib.Plan memory plan) {
        plan = SignatureLib.Plan({
            chainIds: new uint256[](1),
            price: 1 ether,
            period: 1 days,
            token: address(token),
            merchant: merchant,
            salt: 1,
            expiry: 0
        });
        plan.chainIds[0] = block.chainid;
    }

    function _sign(bytes32 digest) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(merchantPk, digest);
        return abi.encodePacked(r, s, v);
    }

    function testSubscribeAndRenew() public {
        SignatureLib.Plan memory plan = _defaultPlan();
        bytes32 planHash = sub.hashPlan(plan);
        bytes memory sig = _sign(planHash);
        vm.prank(user);
        token.approve(address(gateway), plan.price * 2);
        vm.prank(user);
        vm.expectEmit(true, true, false, true);
        emit SubscriptionManager.Subscribed(user, planHash, plan.price, address(token));
        bytes memory empty;
        sub.subscribe(plan, sig, empty);

        (uint256 nextBilling, bytes32 storedHash) = sub.subscribers(user);
        assertEq(storedHash, planHash);
        uint256 expected = nextBilling;

        vm.warp(expected + 1);
        vm.prank(keeper);
        sub.charge(user);
        assertEq(token.balanceOf(merchant), 2 ether);
        (nextBilling, ) = sub.subscribers(user);
        assertEq(nextBilling, expected + plan.period);
    }

    function testUnsubscribe() public {
        SignatureLib.Plan memory plan = _defaultPlan();
        bytes32 planHash = sub.hashPlan(plan);
        bytes memory sig = _sign(planHash);
        vm.prank(user);
        token.approve(address(gateway), plan.price);
        vm.prank(user);
        bytes memory empty;
        sub.subscribe(plan, sig, empty);

        vm.prank(user);
        vm.expectEmit(true, true, false, true);
        emit SubscriptionManager.Unsubscribed(user, planHash);
        sub.unsubscribe();

        bytes32 storedHash;
        (, storedHash) = sub.subscribers(user);
        assertEq(storedHash, bytes32(0));
    }
}

