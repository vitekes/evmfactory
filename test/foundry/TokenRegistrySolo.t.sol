// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {AccessControlCenter} from "contracts/core/AccessControlCenter.sol";
import {TokenRegistry} from "contracts/core/TokenRegistry.sol";

contract TokenRegistrySoloTest is Test {
    AccessControlCenter internal acc;
    TokenRegistry internal reg;
    bytes32 internal constant MODULE_ID = keccak256("Mod");
    address internal t1 = address(0x1);
    address internal t2 = address(0x2);

    function setUp() public {
        acc = new AccessControlCenter();
        acc.initialize(address(this));
        acc.grantRole(acc.FEATURE_OWNER_ROLE(), address(this));
        acc.grantRole(acc.DEFAULT_ADMIN_ROLE(), address(this));
        reg = new TokenRegistry();
        reg.initialize(address(acc));
    }

    function testBulkWhitelist() public {
        address[] memory tokens = new address[](2);
        tokens[0] = t1;
        tokens[1] = t2;
        reg.bulkSetTokenAllowed(MODULE_ID, tokens, true);
        assertTrue(reg.isTokenAllowed(MODULE_ID, t1));
        assertTrue(reg.isTokenAllowed(MODULE_ID, t2));
    }

    function testSetAccessControl() public {
        AccessControlCenter other = new AccessControlCenter();
        other.initialize(address(this));
        vm.prank(address(this));
        reg.setAccessControl(address(other));
        assertEq(address(reg.access()), address(other));
    }
}
