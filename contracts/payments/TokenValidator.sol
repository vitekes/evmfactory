// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './interfaces/ITokenValidator.sol';
import '../core/interfaces/ICoreSystem.sol';
import '../errors/Errors.sol';
import '../lib/Native.sol';
import '../shared/CoreDefs.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

contract TokenValidator is Initializable, UUPSUpgradeable, ITokenValidator {
    ICoreSystem public coreSystem;

    /// @notice Проверяет, разрешен ли токен (альтернативный метод)
    /// @param token Адрес токена
    /// @return Разрешен ли токен
    function isAllowed(address token) external view override returns (bool) {
        return allowedTokens[token];
    }

    // Mapping of token address to allowance status
    mapping(address => bool) private allowedTokens;

    // Array to track all allowed tokens for iteration
    address[] private tokenList;

    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _accessControl) public initializer {
        __UUPSUpgradeable_init();

        if (_accessControl == address(0)) revert ZeroAddress();
        coreSystem = ICoreSystem(_accessControl);
    }

    modifier onlyAdmin() {
        if (!coreSystem.hasRole(0x00, msg.sender)) revert NotAdmin();
        _;
    }

    modifier onlyOperator() {
        if (!coreSystem.hasRole(CoreDefs.OPERATOR_ROLE, msg.sender)) revert NotOperator();
        _;
    }

    /// @notice Check if token is allowed for payments
    /// @param token Token address to check
    /// @return allowed Whether the token is allowed
    function isTokenAllowed(address token) external view override returns (bool allowed) {
        return allowedTokens[token];
    }

    /// @notice Add a token to allowed list
    /// @param token Token address to add
    function addToken(address token) external onlyOperator {
        if (token == address(0)) revert ZeroAddress();
        if (allowedTokens[token]) revert TokenAlreadyAllowed();

        allowedTokens[token] = true;
        tokenList.push(token);

        emit TokenAdded(token);
    }

    /// @notice Remove a token from allowed list
    /// @param token Token address to remove
    function removeToken(address token) external onlyOperator {
        if (token == address(0)) revert ZeroAddress();
        if (!allowedTokens[token]) revert TokenNotAllowed();

        allowedTokens[token] = false;

        // Find and remove token from the list
        for (uint256 i = 0; i < tokenList.length; i++) {
            if (tokenList[i] == token) {
                // Replace with the last element and then pop
                tokenList[i] = tokenList[tokenList.length - 1];
                tokenList.pop();
                break;
            }
        }

        emit TokenRemoved(token);
    }

    /// @notice Get the list of all allowed tokens
    /// @return Array of allowed token addresses
    function getAllowedTokens() external view returns (address[] memory) {
        return tokenList;
    }

    /// @notice Sets a new access control address
    /// @param newAccessControl New access control address
    function setAccessControl(address newAccessControl) external onlyAdmin {
        if (newAccessControl == address(0)) revert ZeroAddress();
        coreSystem = ICoreSystem(newAccessControl);
    }

    /// @notice Checks if a token pair is allowed for conversion
    /// @param fromToken Source token address
    /// @param toToken Destination token address
    /// @return allowed Whether the token pair is allowed
    function isPairAllowed(address fromToken, address toToken) external view override returns (bool allowed) {
        return allowedTokens[fromToken] && allowedTokens[toToken];
    }

    /// @notice Adds a token to the allowed list
    /// @param token Token address to allow
    function allowToken(address token) external override onlyOperator {
        if (token == address(0)) revert ZeroAddress();
        if (allowedTokens[token]) revert TokenAlreadyAllowed();

        allowedTokens[token] = true;
        tokenList.push(token);

        emit TokenAdded(token);
    }

    /// @notice Removes a token from the allowed list
    /// @param token Token address to disallow
    function disallowToken(address token) external override onlyOperator {
        if (token == address(0)) revert ZeroAddress();
        if (!allowedTokens[token]) revert TokenNotAllowed();

        allowedTokens[token] = false;

        // Find and remove token from the list
        for (uint256 i = 0; i < tokenList.length; i++) {
            if (tokenList[i] == token) {
                // Replace with the last element and then pop
                tokenList[i] = tokenList[tokenList.length - 1];
                tokenList.pop();
                break;
            }
        }

        emit TokenRemoved(token);
    }

    /// @notice Checks if a token has been initialized with price feeds
    /// @param token Token address to check
    /// @return isInitialized Whether the token is initialized with price feeds
    function isTokenInitialized(address token) external view override returns (bool isInitialized) {
        // В текущей реализации просто проверяем, что токен есть в списке разрешенных
        return allowedTokens[token];
    }

    /// @notice Authorizes an upgrade to a new implementation
    /// @param newImplementation Address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal view override onlyAdmin {
        if (newImplementation == address(0)) revert InvalidImplementation();
    }
}
