// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../interfaces/IAccessControlCenter.sol';
import '../errors/Errors.sol';

abstract contract AccessManaged {
    address public immutable _ACC;

    constructor(address acc) {
        _ACC = acc;
    }

    function _grantSelfRoles(bytes32[] memory roles) internal {
        IAccessControlCenter(_ACC).grantMultipleRoles(address(this), roles);
    }

    modifier onlyRole(bytes32 role) {
        IAccessControlCenter acc = IAccessControlCenter(_ACC);
        if (!acc.hasRole(role, msg.sender)) revert Forbidden();
        _;
    }
}
