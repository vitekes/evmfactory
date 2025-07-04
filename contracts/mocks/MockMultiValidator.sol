// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../interfaces/IMultiValidator.sol';
import '../interfaces/IAccessControlCenter.sol';

/// @title MockMultiValidator
/// @notice Тестовый валидатор токенов для модульного тестирования
/// @dev Используется только для тестирования, не применять в продакшене
contract MockMultiValidator is IMultiValidator {
    // Маппинг разрешенных токенов
    mapping(address => bool) public allowedTokens;

    // Адрес контракта управления доступом
    address public accessControl;

    /// @notice Инициализирует валидатор
    /// @param acl Адрес контракта управления доступом
    function initialize(address acl) external {
        accessControl = acl;
    }

    /// @notice Устанавливает статус токена (разрешен/запрещен)
    /// @param token Адрес токена
    /// @param allowed Статус разрешения
    function setToken(address token, bool allowed) external {
        allowedTokens[token] = allowed;
    }

    /// @notice Добавляет токен в список разрешенных
    /// @param token Адрес токена
    function addToken(address token) external {
        allowedTokens[token] = true;
    }

    /// @notice Удаляет токен из списка разрешенных
    /// @param token Адрес токена
    function removeToken(address token) external {
        allowedTokens[token] = false;
    }

    /// @notice Массовая установка статуса для нескольких токенов
    /// @param tokens Массив адресов токенов
    /// @param allowed Статус разрешения
    function bulkSetToken(address[] calldata tokens, bool allowed) external {
        for (uint256 i = 0; i < tokens.length; i++) {
            allowedTokens[tokens[i]] = allowed;
        }
    }

    /// @notice Проверяет, разрешен ли токен
    /// @param token Адрес токена для проверки
    /// @return allowed true, если токен разрешен
    function isAllowed(address token) external view returns (bool) {
        return allowedTokens[token];
    }

    /// @notice Проверяет, разрешены ли все токены из массива
    /// @param tokens Массив адресов токенов для проверки
    /// @return allowed true, если все токены разрешены
    function areAllowed(address[] calldata tokens) external view returns (bool) {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (!allowedTokens[tokens[i]]) {
                return false;
            }
        }
        return true;
    }

    /// @notice Устанавливает новый контракт управления доступом
    /// @param newAccess Адрес нового контракта
    function setAccessControl(address newAccess) external {
        accessControl = newAccess;
    }
}
