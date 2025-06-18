// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract MockAccessControlCenter {
    bytes32 public constant FACTORY_ADMIN = keccak256("FACTORY_ADMIN");

    function MODULE_ROLE() external pure returns (bytes32) {
        return keccak256("MODULE_ROLE");
    }

    function FEATURE_OWNER_ROLE() external pure returns (bytes32) {
        return keccak256("FEATURE_OWNER_ROLE");
    }

    function grantMultipleRoles(address, bytes32[] calldata) external {}

    function hasRole(bytes32, address) external pure returns (bool) {
        return true;
    }
}
