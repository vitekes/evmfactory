// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../BaseProcessor.sol';
import '../PaymentContextLibrary.sol';
import '../ProcessorMetadataLib.sol';

/// @title OracleProcessor.sol
/// @notice Процессор для конвертации стоимости между токенами
/// @dev Управляет ценами и курсами обмена между токенами
contract OracleProcessor is BaseProcessor {
    using PaymentContextLibrary for PaymentContextLibrary.PaymentContext;

    // Constants
    bytes32 public constant PRICE_FEEDER_ROLE = keccak256('PRICE_FEEDER_ROLE');
    string private constant _PROCESSOR_NAME = 'PriceOracle';
    string private constant _PROCESSOR_VERSION = '1.0.0';

    // Структура для цены/курса
    struct PriceData {
        uint256 price; // Цена токена в базовой валюте (ETH), умноженная на 10^18
        uint256 timestamp; // Время последнего обновления цены
        uint8 decimals; // Количество десятичных знаков токена
        bool active; // Активен ли оракул для токена
    }

    // State variables
    mapping(bytes32 => mapping(address => PriceData)) public tokenPrices; // moduleId => token => PriceData
    mapping(bytes32 => uint256) public priceValidityPeriod; // moduleId => seconds
    address public constant ETH_ADDRESS = address(0);

    // Events
    event PriceUpdated(bytes32 indexed moduleId, address indexed token, uint256 price, uint8 decimals);
    event ModuleConfigured(bytes32 indexed moduleId, bool enabled, uint256 validityPeriod);
    event PriceConverted(
        bytes32 indexed moduleId,
        address indexed fromToken,
        address indexed toToken,
        uint256 fromAmount,
        uint256 toAmount
    );

    /**
     * @dev Конструктор
     */
    constructor() BaseProcessor() {
        _grantRole(PRICE_FEEDER_ROLE, msg.sender);

        // Устанавливаем цену ETH = 1 ETH (в wei) с 18 десятичными знаками
        PriceData memory ethPrice = PriceData({
            price: 1 * 10 ** 18,
            timestamp: block.timestamp,
            decimals: 18, // ETH имеет 18 десятичных знаков
            active: true
        });

        // Для всех модулей ETH будет иметь одинаковую цену
        // Используем 0 как общий идентификатор для глобальных настроек
        tokenPrices[bytes32(0)][ETH_ADDRESS] = ethPrice;
    }

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
        // Декодируем метаданные для получения информации о конвертации
        bool needsConversion;
        address targetToken;

        // Пробуем получить метаданные из нового формата
        try this.extractOracleMetadata(context.metadata) returns (bool _needsConversion, address _targetToken) {
            needsConversion = _needsConversion;
            targetToken = _targetToken;
        } catch {
            // Для обратной совместимости пробуем старый формат
            try abi.decode(context.metadata, (bool, address)) returns (bool _needsConversion, address _targetToken) {
                needsConversion = _needsConversion;
                targetToken = _targetToken;
            } catch {
                return (ProcessResult.FAILED, _createError(context, 'Invalid metadata format'));
            }
        }

        // Проверяем, что у нас есть актуальные цены для обоих токенов
        if (!isPriceValid(context.moduleId, context.token) || !isPriceValid(context.moduleId, targetToken)) {
            return (ProcessResult.FAILED, _createError(context, 'Price data not available or outdated'));
        }

        // Конвертируем сумму из исходного токена в целевой
        uint256 convertedAmount = convertAmount(context.moduleId, context.token, targetToken, context.processedAmount);

        // Если конвертированная сумма равна 0, платеж неудачен
        if (convertedAmount == 0) {
            return (ProcessResult.FAILED, _createError(context, 'Conversion resulted in zero amount'));
        }

        // Обновляем контекст с новым токеном и суммой
        address originalToken = context.token;
        uint256 originalAmount = context.processedAmount;

        context.token = targetToken;
        context.processedAmount = convertedAmount;
        context.state = PaymentContextLibrary.ProcessingState.CONVERTING;

        // Добавляем результат обработки
        context = PaymentContextLibrary.addProcessorResult(context, getName(), uint8(ProcessResult.MODIFIED));

        // Эмитим событие о конвертации
        emit PriceConverted(context.moduleId, originalToken, targetToken, originalAmount, convertedAmount);

        return (ProcessResult.MODIFIED, abi.encode(context));
    }

    /**
     * @dev Внутренняя реализация проверки применимости
     * @param context Контекст платежа
     * @return applicable Применим ли процессор
     */
    function _isApplicableInternal(
        PaymentContextLibrary.PaymentContext memory context
    ) internal view override returns (bool applicable) {
        // Проверяем, есть ли в метаданных запрос на конвертацию
        if (context.metadata.length == 0) return false;

        // Пробуем найти метаданные для Oracle процессора
        try this.extractOracleMetadata(context.metadata) returns (bool needsConversion, address targetToken) {
            // Процессор применим, если требуется конвертация и токены различаются
            return needsConversion && targetToken != context.token;
        } catch {
            // Пробуем старый формат для обратной совместимости
            try abi.decode(context.metadata, (bool, address)) returns (bool needsConversion, address targetToken) {
                return needsConversion && targetToken != context.token;
            } catch {
                // Если декодирование не удалось, значит метаданные имеют другой формат
                return false;
            }
        }
    }

    /**
     * @notice Настроить процессор для модуля
     * @param moduleId Идентификатор модуля
     * @param config Конфигурация в виде байтов (ожидается: bool enabled, uint256 validityPeriod)
     * @return success Успешность настройки
     */
    function _configureInternal(bytes32 moduleId, bytes calldata config) internal override {
        if (config.length > 0) {
            (bool enabled, uint256 validityPeriod) = abi.decode(config, (bool, uint256));
            priceValidityPeriod[moduleId] = validityPeriod;
            emit ModuleConfigured(moduleId, enabled, validityPeriod);
        }
    }

    /**
     * @notice Обновить цену токена
     * @param moduleId Идентификатор модуля
     * @param token Адрес токена
     * @param price Цена токена (в ETH, умноженная на 10^18)
     * @param decimals Количество десятичных знаков токена
     */
    function updatePrice(bytes32 moduleId, address token, uint256 price, uint8 decimals) external {
        // Проверяем роль с учетом централизованного управления ролями
        require(
            _hasProcessorRole(PRICE_FEEDER_ROLE, msg.sender) || hasRole(PRICE_FEEDER_ROLE, msg.sender),
            'OracleProcessor: caller is not a price feeder'
        );
        require(price > 0, 'PriceOracle: price must be greater than zero');

        tokenPrices[moduleId][token] = PriceData({
            price: price,
            timestamp: block.timestamp,
            decimals: decimals,
            active: true
        });

        emit PriceUpdated(moduleId, token, price, decimals);
    }

    /**
     * @notice Конвертировать сумму из одного токена в другой
     * @param moduleId Идентификатор модуля
     * @param fromToken Исходный токен
     * @param toToken Целевой токен
     * @param amount Сумма в исходном токене
     * @return convertedAmount Сумма в целевом токене
     */
    function convertAmount(
        bytes32 moduleId,
        address fromToken,
        address toToken,
        uint256 amount
    ) public view returns (uint256 convertedAmount) {
        // Если токены совпадают, конвертация не требуется
        if (fromToken == toToken) return amount;

        // Проверяем, что цены действительны
        if (!isPriceValid(moduleId, fromToken) || !isPriceValid(moduleId, toToken)) {
            return 0;
        }

        // Получаем данные о ценах
        PriceData memory fromPrice = getPriceData(moduleId, fromToken);
        PriceData memory toPrice = getPriceData(moduleId, toToken);

        // Конвертируем в ETH (базовую валюту), затем в целевой токен
        // Учитываем разное количество десятичных знаков
        uint256 ethValue = (amount * fromPrice.price) / (10 ** fromPrice.decimals);
        convertedAmount = (ethValue * (10 ** toPrice.decimals)) / toPrice.price;

        return convertedAmount;
    }

    /**
     * @notice Проверить, действительна ли цена токена
     * @param moduleId Идентификатор модуля
     * @param token Адрес токена
     * @return valid Действительна ли цена
     */
    function isPriceValid(bytes32 moduleId, address token) public view returns (bool valid) {
        // Для ETH цена всегда действительна
        if (token == ETH_ADDRESS) return true;

        // Получаем данные о цене
        PriceData memory priceData = getPriceData(moduleId, token);

        // Проверяем, активна ли цена и не устарела ли она
        if (!priceData.active) return false;

        // Получаем период валидности
        uint256 validityPeriod = priceValidityPeriod[moduleId];
        if (validityPeriod == 0) validityPeriod = 1 days; // По умолчанию 1 день

        // Проверяем, не устарела ли цена
        return block.timestamp <= priceData.timestamp + validityPeriod;
    }

    /**
     * @notice Получить данные о цене токена
     * @param moduleId Идентификатор модуля
     * @param token Адрес токена
     * @return priceData Данные о цене
     */
    function getPriceData(bytes32 moduleId, address token) public view returns (PriceData memory priceData) {
        // Проверяем, есть ли специфичная цена для модуля
        priceData = tokenPrices[moduleId][token];

        // Если нет, используем глобальную цену
        if (priceData.timestamp == 0) {
            priceData = tokenPrices[bytes32(0)][token];
        }

        return priceData;
    }

    /**
     * @notice Проверить поддержку пары токенов
     * @param moduleId Идентификатор модуля
     * @param fromToken Исходный токен
     * @param toToken Целевой токен
     * @return supported Поддерживается ли пара
     */
    function isPairSupported(
        bytes32 moduleId,
        address fromToken,
        address toToken
    ) external view returns (bool supported) {
        // Если токены совпадают, пара поддерживается
        if (fromToken == toToken) return true;

        // Проверяем, есть ли действительные цены для обоих токенов
        return isPriceValid(moduleId, fromToken) && isPriceValid(moduleId, toToken);
    }

    /**
     * @notice Получить текущую цену токена
     * @param moduleId Идентификатор модуля
     * @param token Адрес токена
     * @return price Цена токена (в ETH, умноженная на 10^18)
     * @return timestamp Время последнего обновления
     * @return decimals Количество десятичных знаков
     * @return active Активность
     */
    function getTokenPrice(
        bytes32 moduleId,
        address token
    ) external view returns (uint256 price, uint256 timestamp, uint8 decimals, bool active) {
        PriceData memory priceData = getPriceData(moduleId, token);
        return (priceData.price, priceData.timestamp, priceData.decimals, priceData.active);
    }

    /**
     * @notice Извлечь метаданные Oracle процессора из общих метаданных
     * @param metadata Метаданные контекста платежа
     * @return needsConversion Требуется ли конвертация
     * @return targetToken Целевой токен для конвертации
     */
    function extractOracleMetadata(
        bytes memory metadata
    ) external pure returns (bool needsConversion, address targetToken) {
        // Пробуем распаковать как массив метаданных процессоров
        ProcessorMetadataLib.ProcessorMetadata[] memory metadataArray = ProcessorMetadataLib.unpackMetadata(metadata);

        // Ищем метаданные для Oracle процессора
        (bool found, ProcessorMetadataLib.ProcessorMetadata memory oracleMetadata) = ProcessorMetadataLib
            .findMetadataByType(metadataArray, ProcessorMetadataLib.ProcessorType.PRICE_ORACLE);

        if (found) {
            // Распаковываем специфичные данные Oracle процессора
            return abi.decode(oracleMetadata.processorData, (bool, address));
        }

        // Если не найдены метаданные, возвращаем значения по умолчанию
        return (false, address(0));
    }
}
