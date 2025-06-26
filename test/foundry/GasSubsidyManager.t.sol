// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {GasSubsidyManager} from "contracts/core/GasSubsidyManager.sol";
import {AccessControlCenter} from "contracts/core/AccessControlCenter.sol";

import {NotAdmin} from "contracts/errors/Errors.sol";
contract GasSubsidyManagerTest is Test {
    GasSubsidyManager internal gsm;
    AccessControlCenter internal acc;
    address internal user = address(0x1);
    address internal other = address(0x2);

    function setUp() public {
        acc = new AccessControlCenter();
        acc.initialize(address(this));
        acc.grantRole(acc.FEATURE_OWNER_ROLE(), address(this));
        acc.grantRole(acc.AUTOMATION_ROLE(), address(this));
        gsm = new GasSubsidyManager();
        gsm.initialize(address(acc));
    }

    function testSetAndQueryEligibility() public {
        bytes32 moduleId = bytes32("M1");
        gsm.setGasRefundLimit(moduleId, 1 ether);
        gsm.setEligibility(moduleId, user, true);
        gsm.setGasCoverageEnabled(moduleId, address(this), true);
        assertTrue(gsm.isGasFree(moduleId, user, address(this)));
    }

    function testUnauthorizedLimit() public {
        bytes32 moduleId = bytes32("M1");
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(NotAdmin.selector));
        gsm.setGasRefundLimit(moduleId, 1 ether);
    }
}

