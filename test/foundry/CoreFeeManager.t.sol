// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {CoreFeeManager} from "contracts/core/CoreFeeManager.sol";
import {AccessControlCenter} from "contracts/core/AccessControlCenter.sol";
import {NotFeatureOwner} from "contracts/errors/Errors.sol";
import {TestToken} from "contracts/mocks/TestToken.sol";

contract CoreFeeManagerTest is Test {
    CoreFeeManager internal fee;
    AccessControlCenter internal acc;
    TestToken internal t1;
    TestToken internal t2;
    address internal payer = address(0xBEEF);

    function setUp() public {
        acc = new AccessControlCenter();
        acc.initialize(address(this));
        acc.grantRole(acc.FEATURE_OWNER_ROLE(), address(this));
        fee = new CoreFeeManager();
        fee.initialize(address(acc));
        t1 = new TestToken("T1", "T1");
        t2 = new TestToken("T2", "T2");
        t1.transfer(payer, 100 ether);
        t2.transfer(payer, 100 ether);
    }

    function testCollectFee() public {
        fee.setPercentFee(bytes32("M1"), address(t1), 500); // 5%
        fee.setFixedFee(bytes32("M1"), address(t1), 1 ether);
        vm.prank(payer);
        t1.approve(address(fee), 100 ether);
        uint256 f = fee.collect(bytes32("M1"), address(t1), 20 ether);
        assertEq(f, 2 ether); // 1 ether fixed + 5% of 20 = 2
        assertEq(t1.balanceOf(address(fee)), 2 ether);
    }

    function testUnauthorizedSetFee() public {
        address other = address(0xBAD);
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(NotFeatureOwner.selector));
        fee.setPercentFee(bytes32("M1"), address(t2), 100);
    }
}

