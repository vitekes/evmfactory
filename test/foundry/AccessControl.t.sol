// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {AccessControlCenter} from "contracts/core/AccessControlCenter.sol";
import {MultiValidator} from "contracts/core/MultiValidator.sol";
import {PaymentGateway} from "contracts/core/PaymentGateway.sol";
import {CoreFeeManager} from "contracts/core/CoreFeeManager.sol";
import {MockRegistry} from "contracts/mocks/MockRegistry.sol";
import {TestToken} from "contracts/mocks/TestToken.sol";

contract AccessControlTest is Test {
    AccessControlCenter acc;
    MultiValidator validator;
    PaymentGateway gateway;
    CoreFeeManager fee;
    MockRegistry registry;
    TestToken token;

    bytes32 constant MODULE_ID = keccak256("Core");

    function setUp() public {
        acc = new AccessControlCenter();
        acc.initialize(address(this));

        validator = new MultiValidator();
        acc.grantRole(acc.DEFAULT_ADMIN_ROLE(), address(validator));
        validator.initialize(address(acc));

        fee = new CoreFeeManager();
        fee.initialize(address(acc));

        registry = new MockRegistry();
        registry.setCoreService(keccak256(bytes("AccessControlCenter")), address(acc));

        gateway = new PaymentGateway();
        gateway.initialize(address(acc), address(registry), address(fee));

        token = new TestToken("T", "T");
    }

    function testAddTokenNotGovernor() public {
        vm.prank(address(1));
        vm.expectRevert("Forbidden()");
        validator.addToken(address(token));
    }

    function testRemoveTokenNotGovernor() public {
        vm.prank(address(1));
        vm.expectRevert("Forbidden()");
        validator.removeToken(address(token));
    }

    function testProcessPaymentNotFeatureOwner() public {
        vm.prank(address(1));
        vm.expectRevert("Forbidden()");
        gateway.processPayment(MODULE_ID, address(token), address(1), 1 ether, "");
    }
}
