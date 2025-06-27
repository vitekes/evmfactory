// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../shared/AccessManaged.sol';

contract TestAccessManaged is AccessManaged {
    bytes32 public constant FEATURE_OWNER_ROLE = keccak256('FEATURE_OWNER_ROLE');

    constructor(address acc) AccessManaged(acc) {}

    function grantSelf() external {
        bytes32[] memory roles = new bytes32[](1);
        roles[0] = FEATURE_OWNER_ROLE;
        _grantSelfRoles(roles);
    }

    function restricted() external onlyRole(FEATURE_OWNER_ROLE) {}

    function restrictedOther() external onlyRole(keccak256('OTHER_ROLE')) {}
}
