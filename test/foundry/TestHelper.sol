// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlCenter} from "contracts/core/AccessControlCenter.sol";

library TestHelper {
    function setupAclAndRoles(
        AccessControlCenter acl,
        address[] memory governors,
        address[] memory featureOwners,
        address[] memory modules
    ) internal {
        for (uint256 i; i < governors.length; ) {
            acl.grantRole(acl.GOVERNOR_ROLE(), governors[i]);
            unchecked { ++i; }
        }
        for (uint256 i; i < featureOwners.length; ) {
            acl.grantRole(acl.FEATURE_OWNER_ROLE(), featureOwners[i]);
            unchecked { ++i; }
        }
        for (uint256 i; i < modules.length; ) {
            acl.grantRole(acl.MODULE_ROLE(), modules[i]);
            unchecked { ++i; }
        }
    }
}
