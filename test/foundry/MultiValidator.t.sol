// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {AccessControlCenter} from "contracts/core/AccessControlCenter.sol";
import {MultiValidator} from "contracts/core/MultiValidator.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ZeroAddress, NotGovernor, NotAdmin} from "contracts/errors/Errors.sol";

contract MultiValidatorTest is Test {
    AccessControlCenter internal acc;
    MultiValidator internal val;
    address internal admin = address(0xA11CE);
    address internal other = address(0xBEEF);

    function setUp() public {
        vm.startPrank(admin);
        AccessControlCenter accImpl = new AccessControlCenter();
        bytes memory accData = abi.encodeCall(AccessControlCenter.initialize, admin);
        ERC1967Proxy accProxy = new ERC1967Proxy(address(accImpl), accData);
        acc = AccessControlCenter(address(accProxy));
        acc.grantRole(acc.GOVERNOR_ROLE(), admin);
        MultiValidator valImpl = new MultiValidator();
        bytes memory valData = abi.encodeCall(MultiValidator.initialize, address(acc));
        ERC1967Proxy valProxy = new ERC1967Proxy(address(valImpl), valData);
        val = MultiValidator(address(valProxy));
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
        AccessControlCenter newImpl = new AccessControlCenter();
        bytes memory data = abi.encodeCall(AccessControlCenter.initialize, address(0xCAFE));
        ERC1967Proxy proxy = new ERC1967Proxy(address(newImpl), data);
        AccessControlCenter newAcc = AccessControlCenter(address(proxy));
        vm.prank(other);
        vm.expectRevert(NotAdmin.selector);
        val.setAccessControl(address(newAcc));
        vm.prank(admin);
        val.setAccessControl(address(newAcc));
        assertEq(address(val.access()), address(newAcc));
    }
}
