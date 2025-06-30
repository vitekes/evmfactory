// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {BaseFactory} from "contracts/shared/BaseFactory.sol";
import {AccessControlCenter} from "contracts/core/AccessControlCenter.sol";
import {MockRegistry} from "contracts/mocks/MockRegistry.sol";
import {NotFactoryAdmin} from "contracts/errors/Errors.sol";

contract DummyFactory is BaseFactory {
    constructor(address reg, address gateway, bytes32 moduleId)
        BaseFactory(reg, gateway, moduleId)
    {}

    function adminCall() external view onlyFactoryAdmin returns (uint256) {
        return 42;
    }
}

contract TestRegistry is MockRegistry {
    function getFeature(bytes32 id) external view returns (address impl, uint8) {
        impl = features[id];
        require(impl != address(0), "NF");
        return (impl, 1);
    }
}

contract BaseFactoryTest is Test {
    TestRegistry internal registry;
    AccessControlCenter internal acc;
    address internal gateway = address(0x1234);
    bytes32 internal constant MODULE_ID = keccak256("Module");

    function setUp() public {
        acc = new AccessControlCenter();
        acc.initialize(address(this));
        acc.grantRole(acc.FEATURE_OWNER_ROLE(), address(this));
        acc.grantRole(acc.FEATURE_OWNER_ROLE(), address(1));

        registry = new TestRegistry();
        registry.setCoreService(keccak256("AccessControlCenter"), address(acc));
    }

    function testGatewayRegisteredOnDeploy() public {
        registry.registerFeature(MODULE_ID, address(this), 1);
        new DummyFactory(address(registry), gateway, MODULE_ID);
        assertEq(
            registry.getModuleServiceByAlias(MODULE_ID, "PaymentGateway"),
            gateway
        );
    }

    function testNoRegistrationWhenModuleMissing() public {
        new DummyFactory(address(registry), gateway, MODULE_ID);
        assertEq(
            registry.getModuleServiceByAlias(MODULE_ID, "PaymentGateway"),
            address(0)
        );
    }

    function testOnlyFactoryAdmin() public {
        registry.registerFeature(MODULE_ID, address(this), 1);
        DummyFactory f = new DummyFactory(address(registry), gateway, MODULE_ID);
        acc.grantRole(f.FACTORY_ADMIN(), address(this));
        assertEq(f.adminCall(), 42);

        address other = address(0xBEEF);
        vm.prank(other);
        vm.expectRevert(NotFactoryAdmin.selector);
        f.adminCall();
    }
}
