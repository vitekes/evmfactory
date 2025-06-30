// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {AccessControlCenter} from "contracts/core/AccessControlCenter.sol";
import {MultiValidator} from "contracts/core/MultiValidator.sol";

contract MultiValidatorFuzzTest is Test {
    AccessControlCenter internal acc;
    MultiValidator internal val;
    address internal admin = address(0xA11CE);

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

    function testFuzzAddRemoveToken(address token) public {
        vm.assume(token != address(0));
        vm.prank(admin);
        val.addToken(token);
        assertTrue(val.isAllowed(token));

        vm.prank(admin);
        val.removeToken(token);
        assertFalse(val.isAllowed(token));
    }

    function testFuzzBulkSetToken(address t1, address t2) public {
        vm.assume(t1 != address(0) && t2 != address(0) && t1 != t2);
        address[] memory arr = new address[](2);
        arr[0] = t1;
        arr[1] = t2;

        vm.prank(admin);
        val.bulkSetToken(arr, true);
        assertTrue(val.isAllowed(t1));
        assertTrue(val.isAllowed(t2));

        vm.prank(admin);
        val.bulkSetToken(arr, false);
        assertFalse(val.isAllowed(t1));
        assertFalse(val.isAllowed(t2));
    }
}
