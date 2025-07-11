// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../BaseProcessor.sol';
import '../PaymentContextLibrary.sol';
import '../ProcessorMetadataLib.sol';

/// @title TokenFilterProcessor.sol
/// @notice Процессор для проверки поддерживаемых токенов
/// @dev Фильтрует платежи по допустимым токенам
contract TokenFilterProcessor is BaseProcessor {
    using PaymentContextLibrary for PaymentContextLibrary.PaymentContext;

    // Constants
    string private constant _PROCESSOR_NAME = 'TokenFilter';
    string private constant _PROCESSOR_VERSION = '1.0.0';

    // State variables

    // Маппинг moduleId => token => allowed
    mapping(bytes32 => mapping(address => bool)) public allowedTokens;

    // Маппинг moduleId => список токенов
    mapping(bytes32 => address[]) public tokenLists;

    // Events
    event TokenStatusChanged(bytes32 indexed moduleId, address indexed token, bool allowed);

    /**
     * @notice Получить имя процессора
     * @return name Имя процессора
     */
    function getName() public pure override returns (string memory name) {
        return _PROCESSOR_NAME;
    }

    /**
     * @notice Получить версию процессора
     * @return version Версия процессора
     */
    function getVersion() public pure override returns (string memory version) {
        return _PROCESSOR_VERSION;
    }

    /**
     * @dev Внутренняя реализация логики обработки контекста
     * @param context Контекст платежа
     * @return result Результат обработки
     * @return updatedContext Обновленный контекст в байтах
     */
    function _processInternal(
        PaymentContextLibrary.PaymentContext memory context
    ) internal override returns (ProcessResult result, bytes memory updatedContext) {
        // Проверяем наличие метаданных для процессора фильтрации токенов
        bool allowOverride = false;

        if (context.metadata.length > 0) {
            try this.extractTokenFilterMetadata(context.metadata) returns (bool _allowOverride) {
                allowOverride = _allowOverride;
            } catch {
                // Если метаданные не распознаны, используем стандартную логику
            }
        }

        // Если разрешен обход фильтрации, пропускаем проверку
        if (allowOverride) {
            context.state = PaymentContextLibrary.ProcessingState.VALIDATING;
            context = PaymentContextLibrary.addProcessorResult(context, getName(), uint8(ProcessResult.SKIPPED));
            return (ProcessResult.SKIPPED, abi.encode(context));
        }

        // Проверяем, разрешен ли токен для данного модуля
        if (!isTokenAllowed(context.moduleId, context.token)) {
            // Если токен не разрешен, платеж отклоняется
            return (ProcessResult.FAILED, _createError(context, 'Token not allowed'));
        }

        // Токен разрешен, обновляем состояние и продолжаем обработку
        context.state = PaymentContextLibrary.ProcessingState.VALIDATING;
        context = PaymentContextLibrary.addProcessorResult(context, getName(), uint8(ProcessResult.SUCCESS));

        return (ProcessResult.SUCCESS, abi.encode(context));
    }

    /**
     * @dev Внутренняя реализация проверки применимости
     * @param context Контекст платежа
     * @return applicable Применим ли процессор
     */
    function _isApplicableInternal(
        PaymentContextLibrary.PaymentContext memory context
    ) internal view override returns (bool applicable) {
        // Проверяем наличие метаданных для процессора фильтрации токенов
        if (context.metadata.length > 0) {
            try this.extractTokenFilterMetadata(context.metadata) returns (bool allowOverride) {
                // Если указано явное разрешение обойти фильтрацию, процессор не применим
                if (allowOverride) {
                    return false;
                }
            } catch {
                // Если метаданные не распознаны, используем стандартную логику
            }
        }

        return true; // Базовая проверка модуля уже выполнена в родительском классе
    }

    /**
     * @notice Проверить, разрешен ли токен для модуля
     * @param moduleId Идентификатор модуля
     * @param token Адрес токена
     * @return allowed Разрешен ли токен
     */
    function isTokenAllowed(bytes32 moduleId, address token) public view returns (bool allowed) {
        // Проверяем нативную валюту - всегда разрешена
        if (token == address(0)) {
            return true;
        }

        return allowedTokens[moduleId][token];
    }

    /**
     * @notice Разрешить использование токена для модуля
     * @param moduleId Идентификатор модуля
     * @param token Адрес токена
     */
    function allowToken(bytes32 moduleId, address token) external onlyRole(PROCESSOR_ADMIN_ROLE) {
        require(token != address(0), 'TokenFilter: Cannot set native token');

        // Если токен уже разрешен, ничего не делаем
        if (allowedTokens[moduleId][token]) return;

        // Разрешаем токен
        allowedTokens[moduleId][token] = true;

        // Добавляем токен в список
        tokenLists[moduleId].push(token);

        emit TokenStatusChanged(moduleId, token, true);
    }

    /**
     * @notice Запретить использование токена для модуля
     * @param moduleId Идентификатор модуля
     * @param token Адрес токена
     */
    function disallowToken(bytes32 moduleId, address token) external onlyRole(PROCESSOR_ADMIN_ROLE) {
        require(token != address(0), 'TokenFilter: Cannot set native token');

        // Если токен уже запрещен, ничего не делаем
        if (!allowedTokens[moduleId][token]) return;

        // Запрещаем токен
        allowedTokens[moduleId][token] = false;

        // Удаляем токен из списка
        address[] storage tokens = tokenLists[moduleId];
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) {
                // Заменяем последним элементом и удаляем последний
                tokens[i] = tokens[tokens.length - 1];
                tokens.pop();
                break;
            }
        }

        emit TokenStatusChanged(moduleId, token, false);
    }

    /**
     * @notice Получить список разрешенных токенов для модуля
     * @param moduleId Идентификатор модуля
     * @return tokens Список разрешенных токенов
     */
    function getAllowedTokens(bytes32 moduleId) external view returns (address[] memory tokens) {
        return tokenLists[moduleId];
    }

    /**
     * @notice Проверить поддержку пары токенов
     * @param moduleId Идентификатор модуля
     * @param tokenFrom Исходный токен
     * @param tokenTo Целевой токен
     * @return supported Поддерживается ли пара
     */
    function isPairSupported(
        bytes32 moduleId,
        address tokenFrom,
        address tokenTo
    ) external view returns (bool supported) {
        return isTokenAllowed(moduleId, tokenFrom) && isTokenAllowed(moduleId, tokenTo);
    }

    /**
     * @notice Извлечь метаданные фильтра токенов из общих метаданных
     * @param metadata Метаданные контекста платежа
     * @return allowOverride Разрешен ли обход стандартных правил фильтрации
     */
    function extractTokenFilterMetadata(bytes memory metadata) external pure returns (bool allowOverride) {
        // Пробуем распаковать как массив метаданных процессоров
        ProcessorMetadataLib.ProcessorMetadata[] memory metadataArray = ProcessorMetadataLib.unpackMetadata(metadata);

        // Ищем метаданные для процессора фильтрации токенов
        (bool found, ProcessorMetadataLib.ProcessorMetadata memory filterMetadata) = ProcessorMetadataLib
            .findMetadataByType(metadataArray, ProcessorMetadataLib.ProcessorType.TOKEN_FILTER);

        if (found) {
            // Распаковываем специфичные данные процессора фильтрации токенов
            return abi.decode(filterMetadata.processorData, (bool));
        }

        // Если не найдены метаданные, возвращаем значение по умолчанию
        return false;
    }
}
