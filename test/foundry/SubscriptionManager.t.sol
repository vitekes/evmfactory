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

contract SubscriptionManagerTest is Test {
    MockRegistry registry;
    AccessControlCenter acl;
    MockPaymentGateway gateway;
    SubscriptionManager manager;
    MultiValidator validator;
    TestToken token;
    address automationBot = address(this);

    uint256 userPk = 1;
    uint256 merchantPk = 2;
    address user;
    address merchant;

    bytes32 constant MODULE_ID = keccak256("Sub");

    function setUp() public {
        user = vm.addr(userPk);
        merchant = vm.addr(merchantPk);

        acl = new AccessControlCenter();
        acl.initialize(address(this));
        vm.startPrank(address(this));

        registry = new MockRegistry();
        registry.setCoreService(keccak256(bytes("AccessControlCenter")), address(acl));
        gateway = new MockPaymentGateway();
        registry.setModuleServiceAlias(MODULE_ID, "PaymentGateway", address(gateway));

        manager = new SubscriptionManager(address(registry), address(gateway), MODULE_ID);

        address[] memory gov;
        address[] memory fo = new address[](2);
        fo[0] = address(this);
        fo[1] = address(manager);
        address[] memory mods = new address[](1);
        mods[0] = address(manager);
        validator = new MultiValidator();
        acl.grantRole(acl.DEFAULT_ADMIN_ROLE(), address(validator));
        validator.initialize(address(acl));
        registry.setModuleServiceAlias(MODULE_ID, "Validator", address(validator));

        TestHelper.setupAclAndRoles(acl, gov, fo, mods);

        acl.grantRole(acl.FEATURE_OWNER_ROLE(), address(gateway));
        // Additional roles for subscription manager
        TestHelper.grantRolesForModule(
            acl,
            address(manager),
            address(validator),
            automationBot
        );
        acl.grantRole(acl.AUTOMATION_ROLE(), address(manager));

        vm.stopPrank();

        token = new TestToken("Test", "TST");
        token.transfer(user, 10 ether);
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

    function _permitSig(uint256 pk, uint256 value, uint256 deadline) internal view returns (bytes memory) {
        uint256 nonce = token.nonces(user);
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                user,
                address(gateway),
                value,
                nonce,
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encode(deadline, v, r, s);
    }

    function testSubscribeWithPermit() public {
        SignatureLib.Plan memory p = _plan();
        bytes memory sigMerchant = _merchantSig(p);
        uint256 deadline = block.timestamp + 1000;
        bytes memory permitSig = _permitSig(userPk, p.price, deadline);
        vm.prank(user);
        manager.subscribe(p, sigMerchant, permitSig);
        assertEq(token.balanceOf(merchant), p.price);
        (uint256 nextBilling, bytes32 planHash) = manager.subscribers(user);
        assertEq(planHash, manager.hashPlan(p));
        assertEq(nextBilling, block.timestamp + p.period);
    }

    function testSubscribeInvalidPermit() public {
        SignatureLib.Plan memory p = _plan();
        bytes memory sigMerchant = _merchantSig(p);
        uint256 deadline = block.timestamp + 1000;
        bytes memory permitSig = _permitSig(merchantPk, p.price, deadline);
        vm.expectRevert();
        vm.prank(user);
        manager.subscribe(p, sigMerchant, permitSig);
    }
}
