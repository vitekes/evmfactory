// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title Mock Access Control Center
/// @notice Mock implementation of AccessControlCenter for testing
contract MockAccessControlCenter {
    // Role => Account => Has role
    mapping(bytes32 => mapping(address => bool)) private _roles;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant GOVERNOR_ROLE = keccak256('GOVERNOR_ROLE');
    bytes32 public constant FEATURE_OWNER_ROLE = keccak256('FEATURE_OWNER_ROLE');
    bytes32 public constant AUTOMATION_ROLE = keccak256('AUTOMATION_ROLE');
    bytes32 public constant RELAYER_ROLE = keccak256('RELAYER_ROLE');
    bytes32 public constant FACTORY_ADMIN = keccak256('FACTORY_ADMIN');

    function MODULE_ROLE() external pure returns (bytes32) {
        return keccak256('MODULE_ROLE');
    }

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    constructor() {
        // Automatically assign admin role to deployer
        _roles[DEFAULT_ADMIN_ROLE][msg.sender] = true;
        emit RoleGranted(DEFAULT_ADMIN_ROLE, msg.sender, msg.sender);
    }

    function hasRole(bytes32 role, address account) external view returns (bool) {
        return _roles[role][account];
    }

    function grantRole(bytes32 role, address account) external {
        _roles[role][account] = true;
        emit RoleGranted(role, account, msg.sender);
    }

    function revokeRole(bytes32 role, address account) external {
        _roles[role][account] = false;
        emit RoleRevoked(role, account, msg.sender);
    }
}
