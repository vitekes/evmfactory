// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccessControlCenter.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract TokenRegistry is Initializable, UUPSUpgradeable {
    AccessControlCenter public access;

    // moduleId => token => allowed
    mapping(bytes32 => mapping(address => bool)) public isAllowed;

    event TokenWhitelisted(bytes32 indexed moduleId, address indexed token, bool allowed);

    modifier onlyFeatureOwner() {
        require(access.hasRole(access.FEATURE_OWNER_ROLE(), msg.sender), "not feature owner");
        _;
    }

    modifier onlyAdmin() {
        require(access.hasRole(access.DEFAULT_ADMIN_ROLE(), msg.sender), "not admin");
        _;
    }

    function initialize(address accessControl) public initializer {
        __UUPSUpgradeable_init();
        access = AccessControlCenter(accessControl);
    }

    function setTokenAllowed(bytes32 moduleId, address token, bool allowed) external onlyFeatureOwner {
        require(token != address(0), "zero address");
        isAllowed[moduleId][token] = allowed;
        emit TokenWhitelisted(moduleId, token, allowed);
    }

    function bulkSetTokenAllowed(bytes32 moduleId, address[] calldata tokens, bool allowed) external onlyFeatureOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            isAllowed[moduleId][tokens[i]] = allowed;
            emit TokenWhitelisted(moduleId, tokens[i], allowed);
        }
    }

    function isTokenAllowed(bytes32 moduleId, address token) external view returns (bool) {
        return isAllowed[moduleId][token];
    }

    function setAccessControl(address newAccess) external onlyAdmin {
        access = AccessControlCenter(newAccess);
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyAdmin {
        require(newImplementation != address(0), "invalid implementation");
    }

    uint256[50] private __gap;
}
