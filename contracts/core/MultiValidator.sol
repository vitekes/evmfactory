// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../interfaces/ICoreKernel.sol';
import '../errors/Errors.sol';
import '../interfaces/IMultiValidator.sol';
import '../interfaces/IEventRouter.sol';
import '../interfaces/IEventPayload.sol';
import '../interfaces/CoreDefs.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

/// @title MultiValidator
/// @notice Token validator with whitelist for specific modules
/// @dev Used for validating tokens in payment transactions

contract MultiValidator is Initializable, UUPSUpgradeable, IMultiValidator {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    ICoreKernel public core;

    // token => allowed
    mapping(address => bool) public allowed;

    modifier onlyGovernor() {
        if (!core.hasRole(core.GOVERNOR_ROLE(), msg.sender)) revert NotGovernor();
        _;
    }

    modifier onlyAdmin() {
        if (!core.hasRole(core.DEFAULT_ADMIN_ROLE(), msg.sender)) revert NotAdmin();
        _;
    }

    /// @notice Initialize the token validator
    /// @param acl Address of the CoreKernel contract
    function initialize(address acl) external initializer {
        __UUPSUpgradeable_init();
        if (acl == address(0)) revert ZeroAddress();
        core = ICoreKernel(acl);
        // Roles should be granted externally by admin
    }

    /// @notice Initialize the token validator
    /// @param acl Address of the CoreKernel contract
    /// @param registryAddress Unused legacy parameter
    function initialize(address acl, address registryAddress) public initializer {
        __UUPSUpgradeable_init();
        if (acl == address(0)) revert ZeroAddress();
        core = ICoreKernel(acl);
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

    /// @notice Replace the CoreKernel contract
    /// @param newAccess New contract address
    function setAccessControl(address newAccess) external onlyAdmin {
        if (newAccess == address(0)) revert InvalidAddress();
        core = ICoreKernel(newAccess);
    }

    /// @dev Get event router
    /// @return router Event router address or address(0) if not available
    function _getEventRouter() internal view returns (address router) {
        router = core.getCoreService(CoreDefs.SERVICE_EVENT_ROUTER);
    }

    /// @dev Emit token allowed/denied event through EventRouter
    /// @param token Token address
    /// @param status Allowed status
    function _emitTokenEvent(address token, bool status) internal virtual {
        address router = _getEventRouter();
        if (router != address(0)) {
            IEventRouter.EventKind kind = status
                ? IEventRouter.EventKind.TokenAllowed
                : IEventRouter.EventKind.TokenDenied;

            IEventPayload.TokenEvent memory eventData = IEventPayload.TokenEvent({
                tokenAddress: token,
                fromToken: address(0),
                toToken: address(0),
                amount: 0,
                convertedAmount: 0,
                version: 1
            });

            IEventRouter(router).route(kind, abi.encode(eventData));
        }
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyAdmin {
        if (newImplementation == address(0)) revert InvalidImplementation();
    }

    uint256[50] private __gap;
}
