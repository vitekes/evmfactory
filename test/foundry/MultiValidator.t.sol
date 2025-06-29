// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {AccessControlCenter} from "contracts/core/AccessControlCenter.sol";
import {MultiValidator} from "contracts/core/MultiValidator.sol";
import {ZeroAddress, NotGovernor, NotAdmin} from "contracts/errors/Errors.sol";

contract MultiValidatorTest is Test {
    AccessControlCenter internal acc;
    MultiValidator internal val;
    address internal admin = address(0xA11CE);
    address internal other = address(0xBEEF);

    function setUp() public {
        acc = new AccessControlCenter();
        vm.startPrank(admin);
        acc.initialize(admin);
        acc.grantRole(acc.GOVERNOR_ROLE(), admin);
        val = new MultiValidator();
        acc.grantRole(acc.DEFAULT_ADMIN_ROLE(), address(val));
        val.initialize(address(acc));
        vm.stopPrank();
    }

    function testAddRemoveToken() public {
        address token = address(0x1);
        vm.prank(admin);
        val.addToken(token);
        assertTrue(val.isAllowed(token));
        vm.prank(admin);
        val.removeToken(token);
        assertFalse(val.isAllowed(token));
    }

    function testBulkSetToken() public {
        address t1 = address(0x1);
        address t2 = address(0x2);
        address[] memory arr = new address[](2);
        arr[0] = t1;
        arr[1] = t2;
        vm.prank(admin);
        val.bulkSetToken(arr, true);
        assertTrue(val.isAllowed(t1));
        assertTrue(val.isAllowed(t2));
    }

    function testSetTokenZeroReverts() public {
        vm.prank(admin);
        vm.expectRevert(ZeroAddress.selector);
        val.addToken(address(0));
    }

    function testUnauthorizedSetToken() public {
        vm.prank(other);
        vm.expectRevert(NotGovernor.selector);
        val.addToken(address(0x1));
    }

    function testSetAccessControlOnlyAdmin() public {
        AccessControlCenter newAcc = new AccessControlCenter();
        newAcc.initialize(address(0xCAFE));
        vm.prank(other);
        vm.expectRevert(NotAdmin.selector);
        val.setAccessControl(address(newAcc));
        vm.prank(admin);
        val.setAccessControl(address(newAcc));
        assertEq(address(val.access()), address(newAcc));
    }
}
