// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccessControlCenter.sol";

/// @title MultiValidator
/// @notice Module-specific token whitelist deployed via minimal proxy clones.

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract MultiValidator is Initializable, UUPSUpgradeable {
    AccessControlCenter public access;

    // token => allowed
    mapping(address => bool) public allowed;

    event TokenAllowed(address indexed token, bool allowed);

    modifier onlyGovernor() {
        require(access.hasRole(access.GOVERNOR_ROLE(), msg.sender), "not governor");
        _;
    }

    modifier onlyAdmin() {
        require(access.hasRole(access.DEFAULT_ADMIN_ROLE(), msg.sender), "not admin");
        _;
    }

    function initialize(address acl) public initializer {
        __UUPSUpgradeable_init();
        access = AccessControlCenter(acl);
        access.grantRole(access.GOVERNOR_ROLE(), msg.sender);
    }

    function allow(address token, bool status) external onlyGovernor {
        require(token != address(0), "zero address");
        allowed[token] = status;
        emit TokenAllowed(token, status);
    }

    function bulkAllow(address[] calldata tokens, bool status) external onlyGovernor {
        for (uint i = 0; i < tokens.length; i++) {
            allowed[tokens[i]] = status;
            emit TokenAllowed(tokens[i], status);
        }
    }

    function isAllowed(address token) external view returns (bool) {
        return allowed[token];
    }

    function setAccessControl(address newAccess) external onlyAdmin {
        access = AccessControlCenter(newAccess);
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyAdmin {
        require(newImplementation != address(0), "invalid implementation");
    }

    uint256[50] private __gap;
}
