// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {SubscriptionManager} from "contracts/modules/subscriptions/SubscriptionManager.sol";
import {MockRegistry} from "contracts/mocks/MockRegistry.sol";
import {MockAccessControlCenterAuto} from "contracts/mocks/MockAccessControlCenterAuto.sol";
import {MockPaymentGateway} from "contracts/mocks/MockPaymentGateway.sol";
import {TestToken} from "contracts/mocks/TestToken.sol";
import {SignatureLib} from "contracts/lib/SignatureLib.sol";

contract SubscriptionManagerStressTest is Test {
    SubscriptionManager internal sub;
    MockRegistry internal registry;
    MockAccessControlCenterAuto internal acc;
    MockPaymentGateway internal gateway;
    TestToken internal token;

    address internal merchant;
    uint256 internal merchantPk = 1;
    address internal keeper = address(0xCAFE);

    function setUp() public {
        merchant = vm.addr(merchantPk);
        token = new TestToken("T", "T");
        registry = new MockRegistry();
        acc = new MockAccessControlCenterAuto();
        registry.setCoreService(keccak256("AccessControlCenter"), address(acc));
        gateway = new MockPaymentGateway();
        bytes32 moduleId = keccak256("SubStress");
        registry.setModuleServiceAlias(moduleId, "PaymentGateway", address(gateway));
        sub = new SubscriptionManager(address(registry), address(gateway), moduleId);
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

    function _sign(bytes32 digest) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(merchantPk, digest);
        return abi.encodePacked(r, s, v);
    }

    function testChargeBatchStress() public {
        uint256 count = 25;
        SignatureLib.Plan memory plan = _defaultPlan();
        bytes32 planHash = sub.hashPlan(plan);
        bytes memory sig = _sign(planHash);
        address[] memory users = new address[](count);
        for (uint256 i; i < count; ++i) {
            address user = address(uint160(i + 10));
            users[i] = user;
            token.transfer(user, 2 ether);
            vm.startPrank(user);
            token.approve(address(gateway), 2 ether);
            sub.subscribe(plan, sig, "");
            vm.stopPrank();
        }

        vm.prank(address(this));
        sub.setBatchLimit(10);

        (uint256 firstBilling, ) = sub.subscribers(users[0]);
        vm.warp(firstBilling + 1);
        vm.prank(keeper);
        sub.chargeBatch(users);

        assertEq(token.balanceOf(merchant), (count + 10) * 1 ether);
        (uint256 nextBilling, ) = sub.subscribers(users[0]);
        assertEq(nextBilling, firstBilling + plan.period);
        (nextBilling, ) = sub.subscribers(users[count - 1]);
        assertEq(nextBilling, firstBilling); // unchanged
    }
}

