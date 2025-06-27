// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../shared/CloneFactory.sol";

contract DummyTemplate {
    uint256 public value;
    error InitFailed();

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
