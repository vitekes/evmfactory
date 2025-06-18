// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract MockAccessControlCenter {
    function MODULE_ROLE() external pure returns (bytes32) {
        return keccak256("MODULE_ROLE");
    }

    function FEATURE_OWNER_ROLE() external pure returns (bytes32) {
        return keccak256("FEATURE_OWNER_ROLE");
    }

    function grantMultipleRoles(address, bytes32[] calldata) external {}
}
