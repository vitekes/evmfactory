// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '@openzeppelin/contracts/proxy/Clones.sol';
import '../errors/Errors.sol';

abstract contract CloneFactory {
    function _clone(address implementation, bytes32 salt, bytes memory initData) internal returns (address instance) {
        instance = Clones.predictDeterministicAddress(implementation, salt, address(this));
        if (instance.code.length == 0) {
            instance = Clones.cloneDeterministic(implementation, salt);
            if (initData.length > 0) {
                (bool ok, ) = instance.call(initData);
                if (!ok) revert InitFailed();
            }
        }
    }

    function _predict(address implementation, bytes32 salt) internal view returns (address) {
        return Clones.predictDeterministicAddress(implementation, salt, address(this));
    }
}
