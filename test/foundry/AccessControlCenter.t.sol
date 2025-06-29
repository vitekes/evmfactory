// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessControlCenter} from "contracts/core/AccessControlCenter.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";

contract AccessControlCenterTest is Test {
    AccessControlCenter internal acc;
    address internal admin = address(0xA11CE);
    address internal other = address(0xBEEF);

    function setUp() public {
        AccessControlCenter impl = new AccessControlCenter();
        bytes memory data = abi.encodeCall(AccessControlCenter.initialize, admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        acc = AccessControlCenter(address(proxy));
        assertEq(acc.adminAddr(), admin);
    }

    function testGrantAndRevokeRole() public {
        bytes32 role = acc.RELAYER_ROLE();
        vm.prank(admin);
        acc.grantRole(role, other);
        assertTrue(acc.hasRole(role, other));

        vm.prank(admin);
        acc.revokeRole(role, other);
        assertFalse(acc.hasRole(role, other));
    }

    function testUnauthorizedUpgrade() public {
        AccessControlCenter newImpl = new AccessControlCenter();
        vm.prank(other);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                other,
                acc.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(other);
        acc.upgradeToAndCall(address(newImpl), bytes(""));
    }

    function testUpgradeOnImplementationFails() public {
        AccessControlCenter impl = new AccessControlCenter();
        impl.initialize(admin);
        AccessControlCenter newImpl = new AccessControlCenter();
        vm.prank(admin);
        vm.expectRevert(UUPSUpgradeable.UUPSUnauthorizedCallContext.selector);
        impl.upgradeToAndCall(address(newImpl), bytes(""));
    }

    function testReinitializeReverts() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        acc.initialize(admin);
    }
}

