// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {AccessControlCenter} from "contracts/core/AccessControlCenter.sol";
import {CoreFeeManager} from "contracts/core/CoreFeeManager.sol";
import {PaymentGateway} from "contracts/core/PaymentGateway.sol";
import {MockRegistry} from "contracts/mocks/MockRegistry.sol";
import {MockValidator} from "contracts/mocks/MockValidator.sol";
import {TestToken} from "contracts/mocks/TestToken.sol";
import {SignatureLib} from "contracts/lib/SignatureLib.sol";
import {NotAllowedToken, NotFeatureOwner} from "contracts/errors/Errors.sol";

contract PaymentGatewayTest is Test {
    AccessControlCenter internal acc;
    CoreFeeManager internal fee;
    PaymentGateway internal gate;
    MockRegistry internal reg;
    MockValidator internal val;
    TestToken internal token;

    address internal payer = address(0xBEEF);
    uint256 internal payerKey = 0xBEEF;
    address internal relayer = address(0xCAFE);

    bytes32 internal moduleId = keccak256("Mod");

    function setUp() public {
        token = new TestToken("T", "T");
        acc = new AccessControlCenter();
        acc.initialize(address(this));
        acc.grantRole(acc.FEATURE_OWNER_ROLE(), payer);

        fee = new CoreFeeManager();
        fee.initialize(address(acc));
        acc.grantRole(acc.FEATURE_OWNER_ROLE(), address(this));
        fee.setPercentFee(moduleId, address(token), 500); // 5%

        reg = new MockRegistry();
        val = new MockValidator();
        val.setToken(address(token), true);
        reg.setModuleServiceAlias(moduleId, "Validator", address(val));

        gate = new PaymentGateway();
        gate.initialize(address(acc), address(reg), address(fee));
        acc.grantRole(acc.FEATURE_OWNER_ROLE(), address(gate));

        token.transfer(payer, 10 ether);
    }

    function testProcessPayment() public {
        uint256 amount = 1 ether;
        vm.prank(payer);
        token.approve(address(gate), amount);
        vm.prank(payer);
        uint256 net = gate.processPayment(moduleId, address(token), payer, amount, "");
        assertEq(net, 0.95 ether);
        assertEq(token.balanceOf(payer), 9.95 ether);
        assertEq(token.balanceOf(address(fee)), 0.05 ether);
        assertEq(token.balanceOf(address(gate)), 0);
    }

    function testUnauthorizedCaller() public {
        vm.prank(relayer);
        vm.expectRevert(NotFeatureOwner.selector);
        gate.processPayment(moduleId, address(token), relayer, 1 ether, "");
    }

    function testNotAllowedToken() public {
        val.setToken(address(token), false);
        vm.prank(payer);
        token.approve(address(gate), 1 ether);
        vm.prank(payer);
        vm.expectRevert(NotAllowedToken.selector);
        gate.processPayment(moduleId, address(token), payer, 1 ether, "");
    }
}
