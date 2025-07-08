// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ITokenValidator {
    /// @notice Checks if a token is allowed for use in the system
    /// @param token Token address to check
    /// @return allowed Whether the token is allowed
    function isTokenAllowed(address token) external view returns (bool allowed);

    /// @notice Проверяет, разрешен ли токен (альтернативный метод)
    /// @param token Адрес токена
    /// @return Разрешен ли токен
    function isAllowed(address token) external view returns (bool);

    /// @notice Checks if a token pair is allowed for conversion
    /// @param fromToken Source token address
    /// @param toToken Destination token address
    /// @return allowed Whether the token pair is allowed
    function isPairAllowed(address fromToken, address toToken) external view returns (bool allowed);

    /// @notice Adds a token to the allowed list
    /// @param token Token address to allow
    function allowToken(address token) external;

    /// @notice Removes a token from the allowed list
    /// @param token Token address to disallow
    function disallowToken(address token) external;

    /// @notice Checks if a token has been initialized with price feeds
    /// @param token Token address to check
    /// @return isInitialized Whether the token is initialized with price feeds
    function isTokenInitialized(address token) external view returns (bool isInitialized);
}
