// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "contracts/shared/CloneFactory.sol";
import "contracts/errors/Errors.sol";

contract DummyTemplate {
    uint256 public value;

    function init(uint256 v) external {
        if (v == 0) revert InitFailed();
        value = v;
    }
}

contract TestCloneFactory is CloneFactory {
    event Cloned(address indexed implementation, address indexed instance);

    function clone(address impl, bytes32 salt, bytes memory initData) external returns (address) {
        address inst = _clone(impl, salt, initData);
        emit Cloned(impl, inst);
        return inst;
    }

    function predict(address impl, bytes32 salt) external view returns (address) {
        return _predict(impl, salt);
    }
}

contract CloneFactoryTest is Test {
    TestCloneFactory internal factory;
    DummyTemplate internal template;

    function setUp() public {
        factory = new TestCloneFactory();
        template = new DummyTemplate();
    }

    function testCloneSuccess() public {
        bytes32 salt = keccak256("one");
        bytes memory initData = abi.encodeCall(DummyTemplate.init, (42));
        address predicted = factory.predict(address(template), salt);

        vm.expectEmit(true, true, false, false);
        emit TestCloneFactory.Cloned(address(template), predicted);
        address cloneAddr = factory.clone(address(template), salt, initData);
        assertEq(cloneAddr, predicted);
        assertEq(DummyTemplate(cloneAddr).value(), 42);
        assertEq(cloneAddr.code.length, 45);
    }

    function testInitFailure() public {
        bytes32 salt = keccak256("two");
        bytes memory initData = abi.encodeCall(DummyTemplate.init, (0));
        vm.expectRevert(InitFailed.selector);
        factory.clone(address(template), salt, initData);
    }

    function testDifferentSaltsProduceDifferentAddresses() public {
        bytes32 salt1 = bytes32(uint256(1));
        bytes32 salt2 = bytes32(uint256(2));
        address c1 = factory.clone(address(template), salt1, abi.encodeCall(DummyTemplate.init, (1)));
        address c2 = factory.clone(address(template), salt2, abi.encodeCall(DummyTemplate.init, (2)));
        assertTrue(c1 != c2);
    }
}

