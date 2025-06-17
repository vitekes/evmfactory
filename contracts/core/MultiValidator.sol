// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccessControlCenter.sol";

contract MultiValidator {
    AccessControlCenter public access;
    address public owner;

    // moduleId => token => разрешено ли
    mapping(bytes32 => mapping(address => bool)) public isAllowed;

    event TokenAllowed(bytes32 indexed moduleId, address indexed token, bool allowed);

    modifier onlyFeatureOwner() {
        require(access.hasRole(access.FEATURE_OWNER_ROLE(), msg.sender), "not feature owner");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == owner, "not admin");
        _;
    }

    constructor(address accessControl) {
        access = AccessControlCenter(accessControl);
        owner = msg.sender;
    }

    function setAllowed(bytes32 moduleId, address token, bool allowed) external onlyFeatureOwner {
        require(token != address(0), "zero address");
        isAllowed[moduleId][token] = allowed;
        emit TokenAllowed(moduleId, token, allowed);
    }

    function bulkSetAllowed(bytes32 moduleId, address[] calldata tokens, bool allowed) external onlyFeatureOwner {
        for (uint i = 0; i < tokens.length; i++) {
            isAllowed[moduleId][tokens[i]] = allowed;
            emit TokenAllowed(moduleId, tokens[i], allowed);
        }
    }

    function isTokenAllowed(bytes32 moduleId, address token) external view returns (bool) {
        return isAllowed[moduleId][token];
    }

    /// Позволяет заменить AccessControl в случае необходимости
    function setAccessControl(address newAccess) external onlyAdmin {
        access = AccessControlCenter(newAccess);
    }
}
