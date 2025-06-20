// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract MockAccessControlCenterAuto {
    bytes32 public constant FACTORY_ADMIN = keccak256('FACTORY_ADMIN');
    bytes32 public constant GOVERNOR_ROLE = keccak256('GOVERNOR_ROLE');
    bytes32 public constant DEFAULT_ADMIN_ROLE = keccak256('DEFAULT_ADMIN_ROLE');

    function MODULE_ROLE() external pure returns (bytes32) {
        return keccak256('MODULE_ROLE');
    }

    function FEATURE_OWNER_ROLE() external pure returns (bytes32) {
        return keccak256('FEATURE_OWNER_ROLE');
    }

    function RELAYER_ROLE() external pure returns (bytes32) {
        return keccak256('RELAYER_ROLE');
    }

    function AUTOMATION_ROLE() external pure returns (bytes32) {
        return keccak256('AUTOMATION_ROLE');
    }

    function grantMultipleRoles(address, bytes32[] calldata) external {}

    function grantRole(bytes32, address) external {}

    function hasRole(bytes32 role, address) external pure returns (bool) {
        return role == keccak256('FEATURE_OWNER_ROLE') || role == keccak256('AUTOMATION_ROLE');
    }
}
