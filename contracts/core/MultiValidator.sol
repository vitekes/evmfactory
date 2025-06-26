// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './AccessControlCenter.sol';
import '../errors/Errors.sol';

/// @title MultiValidator
/// @notice Module-specific token whitelist deployed via minimal proxy clones.

import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

contract MultiValidator is Initializable, UUPSUpgradeable {
    AccessControlCenter public access;

    // token => allowed
    mapping(address => bool) public allowed;

    event TokenAllowed(address indexed token, bool allowed);

    modifier onlyGovernor() {
        if (!access.hasRole(access.GOVERNOR_ROLE(), msg.sender)) revert NotGovernor();
        _;
    }

    modifier onlyAdmin() {
        if (!access.hasRole(access.DEFAULT_ADMIN_ROLE(), msg.sender)) revert NotAdmin();
        _;
    }

    /// @notice Initialize the validator
    /// @param acl Address of AccessControlCenter
    function initialize(address acl) public initializer {
        __UUPSUpgradeable_init();
        access = AccessControlCenter(acl);
        access.grantRole(access.GOVERNOR_ROLE(), msg.sender);
    }

    /// @notice Allow or disallow a token
    /// @param token Token address
    /// @param status Whether the token is allowed
    function setToken(address token, bool status) public onlyGovernor {
        if (token == address(0)) revert ZeroAddress();
        allowed[token] = status;
        emit TokenAllowed(token, status);
    }

    /// @notice Add a token to the allowed list
    /// @param token Token address
    function addToken(address token) external onlyGovernor {
        setToken(token, true);
    }

    /// @notice Remove a token from the allowed list
    /// @param token Token address
    function removeToken(address token) external onlyGovernor {
        setToken(token, false);
    }

    /// @notice Bulk set token allowance
    /// @param tokens Token addresses
    /// @param status Allowance flag
    function bulkSetToken(address[] calldata tokens, bool status) external onlyGovernor {
        for (uint i = 0; i < tokens.length; i++) {
            setToken(tokens[i], status);
        }
    }

    /// @notice Check if a token is allowed
    /// @param token Token address
    /// @return True if allowed
    function isAllowed(address token) external view returns (bool) {
        return allowed[token];
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
