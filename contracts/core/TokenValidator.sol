// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './AccessControlCenter.sol';
import '../errors/Errors.sol';
import '../interfaces/ITokenValidator.sol';
import '../interfaces/CoreDefs.sol';
import '../interfaces/IRegistry.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

/// @title TokenValidator.sol
/// @notice Token validator with whitelist for specific modules
/// @dev Used for validating tokens in payment transactions

contract TokenValidator is Initializable, UUPSUpgradeable, ITokenValidator {
    // Events for tracking token status changes
    event TokenAllowed(address indexed token, bytes32 indexed moduleId);
    event TokenDenied(address indexed token, bytes32 indexed moduleId);

    // Module identifier
    bytes32 public moduleId = keccak256('VALIDATOR');
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    AccessControlCenter public access;
    IRegistry public registry;

    // token => allowed
    mapping(address => bool) public allowed;

    modifier onlyGovernor() {
        if (!access.hasRole(access.GOVERNOR_ROLE(), msg.sender)) revert NotGovernor();
        _;
    }

    modifier onlyAdmin() {
        if (!access.hasRole(access.DEFAULT_ADMIN_ROLE(), msg.sender)) revert NotAdmin();
        _;
    }

    /// @notice Initialize the token validator
    /// @param acl Address of the access control contract (AccessControlCenter)
    function initialize(address acl) external initializer {
        __UUPSUpgradeable_init();
        if (acl == address(0)) revert ZeroAddress();
        access = AccessControlCenter(acl);
        // Roles should be granted externally by admin
    }

    /// @notice Initialize the token validator
    /// @param acl Address of the access control contract (AccessControlCenter)
    /// @param registryAddress Address of the registry contract
    function initialize(address acl, address registryAddress) public initializer {
        __UUPSUpgradeable_init();
        if (acl == address(0)) revert ZeroAddress();
        access = AccessControlCenter(acl);

        if (registryAddress != address(0)) {
            registry = IRegistry(registryAddress);
        }
        // Roles should be granted externally by admin
    }

    /// @notice Allow or disallow a token
    /// @param token Token address
    /// @param status Whether the token is allowed
    function setToken(address token, bool status) public onlyGovernor {
        if (token == address(0)) revert ZeroAddress();
        allowed[token] = status;
        _emitTokenEvent(token, status);
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
        for (uint256 i = 0; i < tokens.length; i++) {
            setToken(tokens[i], status);
        }
    }

    /// @notice Check if a token is allowed
    /// @param token Token address
    /// @return True if allowed
    function isAllowed(address token) external view returns (bool) {
        return allowed[token];
    }

    /// @notice Check permissions for a list of tokens
    /// @param tokens Array of token addresses to check
    /// @return true if all tokens in the list are allowed
    function areAllowed(address[] calldata tokens) external view returns (bool) {
        uint256 length = tokens.length;
        if (length == 0) return true;

        for (uint256 i = 0; i < length; i++) {
            address token = tokens[i];
            if (token == address(0)) revert ZeroAddress();
            if (!allowed[token]) return false;
        }
        return true;
    }

    /// @notice Replace the AccessControlCenter contract
    /// @param newAccess New contract address
    function setAccessControl(address newAccess) external onlyAdmin {
        if (newAccess == address(0)) revert InvalidAddress();
        access = AccessControlCenter(newAccess);
    }

    /// @notice Set registry address
    /// @param registryAddress New registry address
    function setRegistry(address registryAddress) external onlyAdmin {
        if (registryAddress == address(0)) revert ZeroAddress();
        registry = IRegistry(registryAddress);
    }

    /// @dev Emit token allowed/denied event directly
    /// @param token Token address
    /// @param status Allowed status
    function _emitTokenEvent(address token, bool status) internal virtual {
        if (status) {
            emit TokenAllowed(token, moduleId);
        } else {
            emit TokenDenied(token, moduleId);
        }
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyAdmin {
        if (newImplementation == address(0)) revert InvalidImplementation();
    }

    uint256[50] private __gap;
}
