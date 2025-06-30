// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './AccessControlCenter.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '../errors/Errors.sol';

contract TokenRegistry is Initializable, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    AccessControlCenter public access;

    // moduleId => token => allowed
    mapping(bytes32 => mapping(address => bool)) public isAllowed;

    event TokenWhitelisted(bytes32 indexed moduleId, address indexed token, bool allowed);

    modifier onlyFeatureOwner() {
        if (!access.hasRole(access.FEATURE_OWNER_ROLE(), msg.sender)) revert NotFeatureOwner();
        _;
    }

    modifier onlyAdmin() {
        if (!access.hasRole(access.DEFAULT_ADMIN_ROLE(), msg.sender)) revert NotAdmin();
        _;
    }

    /// @notice Initialize the registry
    /// @param accessControl Address of AccessControlCenter
    function initialize(address accessControl) public initializer {
        __UUPSUpgradeable_init();
        access = AccessControlCenter(accessControl);
    }

    /// @notice Allow or disallow a token for a module
    /// @param moduleId Module identifier
    /// @param token Token address
    /// @param allowed Allow flag
    function setTokenAllowed(bytes32 moduleId, address token, bool allowed) external onlyFeatureOwner {
        if (token == address(0)) revert ZeroAddress();
        isAllowed[moduleId][token] = allowed;
        emit TokenWhitelisted(moduleId, token, allowed);
    }

    /// @notice Bulk update token allowance for a module
    /// @param moduleId Module identifier
    /// @param tokens Token addresses
    /// @param allowed Allow flag
    function bulkSetTokenAllowed(bytes32 moduleId, address[] calldata tokens, bool allowed) external onlyFeatureOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            isAllowed[moduleId][tokens[i]] = allowed;
            emit TokenWhitelisted(moduleId, tokens[i], allowed);
        }
    }

    /// @notice Check if token is allowed for module
    /// @param moduleId Module identifier
    /// @param token Token address
    /// @return True if allowed
    function isTokenAllowed(bytes32 moduleId, address token) external view returns (bool) {
        return isAllowed[moduleId][token];
    }

    /// @notice Replace the AccessControlCenter contract
    /// @param newAccess New contract address
    function setAccessControl(address newAccess) external onlyAdmin {
        if (newAccess == address(0)) revert InvalidAddress();
        access = AccessControlCenter(newAccess);
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyAdmin {
        if (newImplementation == address(0)) revert InvalidImplementation();
    }

    uint256[50] private __gap;
}
