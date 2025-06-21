// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {SubscriptionManager} from "contracts/modules/subscriptions/SubscriptionManager.sol";
import {MockRegistry} from "contracts/mocks/MockRegistry.sol";
import {AccessControlCenter} from "contracts/core/AccessControlCenter.sol";
import {MockPaymentGateway} from "contracts/mocks/MockPaymentGateway.sol";
import {TestToken} from "contracts/mocks/TestToken.sol";
import {MultiValidator} from "contracts/core/MultiValidator.sol";
import {SignatureLib} from "contracts/lib/SignatureLib.sol";
import {TestHelper} from "./TestHelper.sol";
import "contracts/errors/Errors.sol" as Errors;

contract SubscriptionBatchTest is Test {
    MockRegistry registry;
    AccessControlCenter acl;
    MockPaymentGateway gateway;
    SubscriptionManager manager;
    MultiValidator validator;
    TestToken token;
    address automationBot = address(this);

    uint256 merchantPk = 1;
    address merchant;

    bytes32 constant MODULE_ID = keccak256("Sub");

    function setUp() public {
        merchant = vm.addr(merchantPk);

        acl = new AccessControlCenter();
        acl.initialize(address(this));
        vm.startPrank(address(this));

        registry = new MockRegistry();
        registry.setCoreService(keccak256(bytes("AccessControlCenter")), address(acl));
        gateway = new MockPaymentGateway();
        registry.setModuleServiceAlias(MODULE_ID, "PaymentGateway", address(gateway));

        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        acl.grantRole(acl.DEFAULT_ADMIN_ROLE(), predicted);
        manager = new SubscriptionManager(address(registry), address(gateway), MODULE_ID);
        validator = new MultiValidator();
        acl.grantRole(acl.DEFAULT_ADMIN_ROLE(), address(validator));
        validator.initialize(address(acl));
        registry.setModuleServiceAlias(MODULE_ID, "Validator", address(validator));

        address[] memory gov;
        address[] memory fo = new address[](2);
        fo[0] = address(this);
        fo[1] = address(manager);
        address[] memory mods = new address[](1);
        mods[0] = address(manager);
        TestHelper.setupAclAndRoles(acl, gov, fo, mods);
        acl.grantRole(acl.FEATURE_OWNER_ROLE(), address(gateway));
        // Additional roles for subscription tests
        TestHelper.grantRolesForModule(
            acl,
            address(manager),
            address(validator),
            automationBot
        );
        // Existing automation permissions
        acl.grantRole(acl.AUTOMATION_ROLE(), address(manager));

        vm.stopPrank();

        token = new TestToken("Test", "TST");

        token = new TestToken("Test", "TST");
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

    function _subscribeUsers(uint256 count) internal returns (address[] memory addrs) {
        SignatureLib.Plan memory p = _plan();
        bytes memory sigMerchant = _merchantSig(p);

        addrs = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            address user = vm.addr(uint256(100 + i));
            addrs[i] = user;
            token.transfer(user, 10 ether);
            vm.startPrank(user);
            token.approve(address(gateway), type(uint256).max);
            manager.subscribe(p, sigMerchant, "");
            vm.stopPrank();
        }
    }

    function _warpToNextPeriod(SignatureLib.Plan memory p) internal {
        vm.warp(block.timestamp + p.period);
    }

    function testChargeBatchLessThanLimit() public {
        address[] memory users = _subscribeUsers(3);
        SignatureLib.Plan memory p = _plan();
        manager.setBatchLimit(5);
        _warpToNextPeriod(p);
        uint256 bal0 = token.balanceOf(merchant);
        manager.chargeBatch(users);
        uint256 bal1 = token.balanceOf(merchant);
        assertEq(bal1 - bal0, p.price * users.length);
    }

    function testChargeBatchExactLimit() public {
        address[] memory users = _subscribeUsers(5);
        SignatureLib.Plan memory p = _plan();
        manager.setBatchLimit(5);
        _warpToNextPeriod(p);
        uint256 bal0 = token.balanceOf(merchant);
        manager.chargeBatch(users);
        uint256 bal1 = token.balanceOf(merchant);
        assertEq(bal1 - bal0, p.price * users.length);
    }

    function testChargeBatchExcessLimit() public {
        address[] memory users = _subscribeUsers(7);
        SignatureLib.Plan memory p = _plan();
        manager.setBatchLimit(5);
        _warpToNextPeriod(p);
        uint256 bal0 = token.balanceOf(merchant);
        manager.chargeBatch(users);
        uint256 bal1 = token.balanceOf(merchant);
        assertEq(bal1 - bal0, p.price * 5);
        for (uint256 i = 0; i < users.length; i++) {
            (uint256 nextBilling,) = manager.subscribers(users[i]);
            if (i < 5) {
                assertEq(nextBilling, block.timestamp + p.period);
            } else {
                assertEq(nextBilling, block.timestamp); // unchanged (since warp sets to block.timestamp)
            }
        }
    }

    function testChargeBatchNotDue() public {
        address[] memory users = _subscribeUsers(2);
        manager.setBatchLimit(5);
        vm.expectRevert("NotDue()");
        manager.chargeBatch(users);
    }

    function testChargeBatchNotAutomation() public {
        address[] memory users = new address[](1);
        users[0] = address(1);
        vm.prank(address(1));
        vm.expectRevert(Errors.NotAutomation.selector);
        manager.chargeBatch(users);
    }
}
