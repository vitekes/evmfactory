// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {PaymentGateway} from "contracts/core/PaymentGateway.sol";
import {CoreFeeManager} from "contracts/core/CoreFeeManager.sol";
import {MultiValidator} from "contracts/core/MultiValidator.sol";
import {MockRegistry} from "contracts/mocks/MockRegistry.sol";
import {MockAccessControlCenter} from "contracts/mocks/MockAccessControlCenter.sol";
import {TestToken} from "contracts/mocks/TestToken.sol";

contract CorePaymentProcessorTest is Test {
    PaymentGateway gateway;
    CoreFeeManager fee;
    MultiValidator validator;
    MockRegistry registry;
    MockAccessControlCenter acc;
    TestToken token;

    bytes32 constant MODULE_ID = keccak256("Core");

    function setUp() public {
        acc = new MockAccessControlCenter();
        registry = new MockRegistry();
        registry.setCoreService(keccak256(bytes("AccessControlCenter")), address(acc));

        fee = new CoreFeeManager();
        fee.initialize(address(acc));

        gateway = new PaymentGateway();
        gateway.initialize(address(acc), address(registry), address(fee));

        validator = new MultiValidator();
        validator.initialize(address(acc));
        registry.setModuleServiceAlias(MODULE_ID, "Validator", address(validator));
        registry.setModuleServiceAlias(MODULE_ID, "PaymentGateway", address(gateway));

        token = new TestToken("Test", "TST");
        validator.addToken(address(token));
    }

    function testProcessPaymentHappy() public {
        fee.setPercentFee(MODULE_ID, address(token), 1000); // 10%
        uint256 start = token.balanceOf(address(this));
        token.approve(address(gateway), 100 ether);

        uint256 net = gateway.processPayment(MODULE_ID, address(token), address(this), 100 ether, "");
        assertEq(net, 90 ether);
        assertEq(token.balanceOf(address(this)), start - 10 ether);
    }

    function testProcessPaymentNotWhitelisted() public {
        TestToken bad = new TestToken("Bad", "BAD");
        bad.approve(address(gateway), 1 ether);
        vm.expectRevert("NotAllowedToken()");
        gateway.processPayment(MODULE_ID, address(bad), address(this), 1 ether, "");
    }
}
