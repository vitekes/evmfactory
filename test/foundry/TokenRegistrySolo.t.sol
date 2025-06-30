// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {AccessControlCenter} from "contracts/core/AccessControlCenter.sol";
import {TokenRegistry} from "contracts/core/TokenRegistry.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract TokenRegistrySoloTest is Test {
    AccessControlCenter internal acc;
    TokenRegistry internal reg;
    bytes32 internal constant MODULE_ID = keccak256("Mod");
    address internal t1 = address(0x1);
    address internal t2 = address(0x2);

    function setUp() public {
        AccessControlCenter accImpl = new AccessControlCenter();
        bytes memory accData = abi.encodeCall(AccessControlCenter.initialize, address(this));
        ERC1967Proxy accProxy = new ERC1967Proxy(address(accImpl), accData);
        acc = AccessControlCenter(address(accProxy));
        acc.grantRole(acc.FEATURE_OWNER_ROLE(), address(this));
        acc.grantRole(acc.DEFAULT_ADMIN_ROLE(), address(this));
        TokenRegistry regImpl = new TokenRegistry();
        bytes memory regData = abi.encodeCall(TokenRegistry.initialize, address(acc));
        ERC1967Proxy regProxy = new ERC1967Proxy(address(regImpl), regData);
        reg = TokenRegistry(address(regProxy));
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
        AccessControlCenter otherImpl = new AccessControlCenter();
        bytes memory data = abi.encodeCall(AccessControlCenter.initialize, address(this));
        ERC1967Proxy proxy = new ERC1967Proxy(address(otherImpl), data);
        AccessControlCenter other = AccessControlCenter(address(proxy));
        vm.prank(address(this));
        reg.setAccessControl(address(other));
        assertEq(address(reg.access()), address(other));
    }
}
