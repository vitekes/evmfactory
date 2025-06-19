// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../core/AccessControlCenter.sol";
import "../errors/Errors.sol";

abstract contract AccessManaged {
    address public immutable _ACC;

    constructor(address acc) {
        _ACC = acc;
    }

    function _grantSelfRoles(bytes32[] memory roles) internal {
        AccessControlCenter(_ACC).grantMultipleRoles(address(this), roles);
    }

    modifier onlyRole(bytes32 role) {
        AccessControlCenter acc = AccessControlCenter(_ACC);
        if (!acc.hasRole(role, msg.sender)) revert Forbidden();
        _;
    }
}
