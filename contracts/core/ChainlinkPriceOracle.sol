// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../interfaces/IPriceOracle.sol';
import '../interfaces/AggregatorV3Interface.sol';
import '../core/AccessControlCenter.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '../errors/Errors.sol';

/// @title Chainlink Price Oracle
/// @notice Упрощенный оракул цен с использованием Chainlink price feeds
contract ChainlinkPriceOracle is IPriceOracle {
    /// @notice Контракт управления доступом
    AccessControlCenter public immutable accessControl;

    /// @notice Максимальный возраст данных цены в секундах
    uint256 public constant MAX_PRICE_AGE = 24 hours;

    /// @notice Адрес прайс-фида Chainlink для каждого токена
    mapping(address => address) public priceFeeds;

    /// @notice Базовый токен для каждого прайс-фида
    mapping(address => address) public baseTokens;

    /// @notice Инициализация оракула
    /// @param _accessControl Адрес контракта управления доступом
    constructor(address _accessControl) {
        if (_accessControl == address(0)) revert InvalidAddress();
        accessControl = AccessControlCenter(_accessControl);
    }

    /// @notice Установить прайс-фид для токена
    /// @param token Адрес токена
    /// @param priceFeed Адрес прайс-фида Chainlink
    /// @param baseToken Адрес базового токена (например, USDC для USD фидов)
    function setPriceFeed(address token, address priceFeed, address baseToken) external {
        if (!accessControl.hasRole(accessControl.GOVERNOR_ROLE(), msg.sender)) revert NotGovernor();
        if (token == address(0) || priceFeed == address(0) || baseToken == address(0)) revert InvalidAddress();

        priceFeeds[token] = priceFeed;
        baseTokens[token] = baseToken;
    }

    /// @notice Получить цену для пары токенов
    /// @param token Токен для получения цены
    /// @param baseToken Базовый токен для сравнения
    /// @return price Цена с учетом decimals
    /// @return decimals Количество десятичных знаков в цене
    function getPrice(address token, address baseToken) public view override returns (uint256 price, uint8 decimals) {
        // Если токены совпадают, возвращаем 1:1
        if (token == baseToken) {
            return (10 ** IERC20Metadata(token).decimals(), IERC20Metadata(token).decimals());
        }

        // Проверяем наличие прямого фида
        address directFeed = priceFeeds[token];
        address directBase = baseTokens[token];

        // Проверяем поддержку пары
        if (directFeed == address(0) || directBase != baseToken) revert UnsupportedPair();

        // Получаем данные из Chainlink
        AggregatorV3Interface feed = AggregatorV3Interface(directFeed);
        (uint80 roundId, int256 answer, , uint256 updatedAt, uint80 answeredInRound) = feed.latestRoundData();

        // Проверяем корректность данных
        if (answer <= 0) revert InvalidPrice();
        if (updatedAt < block.timestamp - MAX_PRICE_AGE) revert StalePrice();
        if (answeredInRound < roundId) revert StalePrice();

        return (uint256(answer), feed.decimals());
    }

    /// @notice Конвертировать сумму из одного токена в другой
    /// @param fromToken Исходный токен
    /// @param toToken Целевой токен
    /// @param amount Сумма для конвертации
    /// @return convertedAmount Сумма в целевом токене
    function convertAmount(
        address fromToken,
        address toToken,
        uint256 amount
    ) public view override returns (uint256 convertedAmount) {
        // Если токены совпадают, возвращаем исходную сумму
        if (fromToken == toToken) return amount;

        // Получаем общий базовый токен
        address fromBase = baseTokens[fromToken];
        address toBase = baseTokens[toToken];

        // Проверяем совместимость базовых токенов
        if (fromBase == address(0) || toBase == address(0) || fromBase != toBase) revert UnsupportedPair();

        // Получаем цены и информацию о decimals
        (uint256 fromPrice, uint8 fromDecimals) = getPrice(fromToken, fromBase);
        (uint256 toPrice, uint8 toDecimals) = getPrice(toToken, fromBase);
        uint8 fromTokenDecimals = IERC20Metadata(fromToken).decimals();
        uint8 toTokenDecimals = IERC20Metadata(toToken).decimals();

        // Конвертируем через базовый токен
        uint256 baseAmount = (amount * fromPrice) / (10 ** fromDecimals);
        uint256 adjustedForDecimals = (baseAmount * (10 ** toTokenDecimals)) / (10 ** fromTokenDecimals);
        return (adjustedForDecimals * (10 ** toDecimals)) / toPrice;
    }

    /// @notice Проверить поддержку пары токенов
    /// @param token Токен для проверки
    /// @param baseToken Базовый токен для проверки
    /// @return supported True, если пара поддерживается
    function isPairSupported(address token, address baseToken) external view override returns (bool) {
        if (token == baseToken) return true;
        address feed = priceFeeds[token];
        address tokenBase = baseTokens[token];
        return feed != address(0) && tokenBase == baseToken;
    }

    /// @notice Расширенная конвертация с поддержкой fallback через промежуточный токен
    /// @param fromToken Исходный токен
    /// @param toToken Целевой токен
    /// @param intermediateToken Промежуточный токен для конвертации
    /// @param amount Сумма для конвертации
    /// @return Сумма в целевом токене
    function convertAmountWithIntermediateToken(
        address fromToken,
        address toToken,
        address intermediateToken,
        uint256 amount
    ) external view returns (uint256) {
        // Для идентичных токенов
        if (fromToken == toToken) return amount;

        // Проверяем валидность промежуточного токена
        if (intermediateToken == address(0)) revert InvalidAddress();

        // Пробуем прямую конвертацию
        try this.convertAmount(fromToken, toToken, amount) returns (uint256 result) {
            return result;
        } catch {
            // Конвертируем через промежуточный токен
            return _convertViaIntermediateToken(fromToken, toToken, intermediateToken, amount);
        }
    }

    /// @dev Вспомогательная функция для конвертации через промежуточный токен
    function _convertViaIntermediateToken(
        address fromToken,
        address toToken,
        address intermediateToken,
        uint256 amount
    ) private view returns (uint256) {
        try this.convertAmount(fromToken, intermediateToken, amount) returns (uint256 intermediateAmount) {
            try this.convertAmount(intermediateToken, toToken, intermediateAmount) returns (uint256 result) {
                return result;
            } catch {
                revert UnsupportedPair();
            }
        } catch {
            revert UnsupportedPair();
        }
    }
}
