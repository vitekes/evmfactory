// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {AccessControlCenter} from "contracts/core/AccessControlCenter.sol";
import {Registry} from "contracts/core/Registry.sol";
import {TokenRegistry} from "contracts/core/TokenRegistry.sol";
import {InvalidImplementation, InvalidAddress, NotFound} from "contracts/errors/Errors.sol";

contract RegistryTest is Test {
    AccessControlCenter internal acc;
    Registry internal registry;
    TokenRegistry internal tokenReg;
    bytes32 internal constant FEATURE_ID = keccak256("Feature1");
    bytes32 internal constant MODULE_ID = keccak256("Module1");
    address internal featureImpl = address(0x1234);
    address internal newImpl = address(0x5678);
    address internal token = address(0xCAFE);

    function setUp() public {
        acc = new AccessControlCenter();
        acc.initialize(address(this));
        acc.grantRole(acc.FEATURE_OWNER_ROLE(), address(this));

        registry = new Registry();
        registry.initialize(address(acc));

        tokenReg = new TokenRegistry();
        tokenReg.initialize(address(acc));
    }

    function testRegisterAndUpgradeFeature() public {
        vm.expectEmit(true, true, false, true);
        emit Registry.FeatureRegistered(FEATURE_ID, featureImpl, 1);
        registry.registerFeature(FEATURE_ID, featureImpl, 1);

        vm.expectEmit(true, true, true, true);
        emit Registry.FeatureUpdated(FEATURE_ID, featureImpl, newImpl);
        registry.upgradeFeature(FEATURE_ID, newImpl);

        (address impl, uint8 ctx) = registry.getFeature(FEATURE_ID);
        assertEq(impl, newImpl);
        assertEq(ctx, 1);
    }

    function testTokenWhitelist() public {
        vm.expectEmit(true, true, false, true);
        emit TokenRegistry.TokenWhitelisted(MODULE_ID, token, true);
        tokenReg.setTokenAllowed(MODULE_ID, token, true);
        assertTrue(tokenReg.isTokenAllowed(MODULE_ID, token));

        address[] memory tokens = new address[](1);
        tokens[0] = token;
        vm.expectEmit(true, true, false, true);
        emit TokenRegistry.TokenWhitelisted(MODULE_ID, token, false);
        tokenReg.bulkSetTokenAllowed(MODULE_ID, tokens, false);
        assertFalse(tokenReg.isTokenAllowed(MODULE_ID, token));
    }

    function testUpgradeFeatureInvalidAddress() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidAddress.selector));
        registry.upgradeFeature(FEATURE_ID, address(0));
    }

    function testGetFeatureNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(NotFound.selector));
        registry.getFeature(FEATURE_ID);
    }
}
