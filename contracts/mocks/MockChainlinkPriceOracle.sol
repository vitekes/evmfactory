// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../interfaces/IPriceOracle.sol';
import '@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';

/// @title MockChainlinkPriceOracle
/// @notice Тестовый мок для ChainlinkPriceOracle - только для использования в тестах
contract ChainlinkPriceFeed is IPriceOracle {
    // Маппинг токен => адрес агрегатора
    mapping(address => address) public aggregators;
    // Маппинг токен => базовый токен
    mapping(address => address) public baseTokens;

    function setAggregator(address token, address feed, address baseToken) external {
        aggregators[token] = feed;
        baseTokens[token] = baseToken;
    }

    /// @notice Получить цену в USD (устаревший метод, для обратной совместимости)
    function tokenPriceUsd(address token) external view returns (uint256) {
        address feed = aggregators[token];
        if (feed == address(0)) return 0;
        (, int256 answer, , , ) = AggregatorV3Interface(feed).latestRoundData();
        uint8 decimals = AggregatorV3Interface(feed).decimals();
        if (answer <= 0) return 0;
        return uint256(answer) * (10 ** (18 - decimals));
    }

    /// @notice Get price for a token pair
    /// @param token Token to get price for
    /// @param baseToken Base token to compare against
    /// @return price Price with decimals
    /// @return decimals Number of decimals in the price
    function getPrice(address token, address baseToken) external view returns (uint256 price, uint8 decimals) {
        // Если токены совпадают, возвращаем 1:1
        if (token == baseToken) {
            return (10**IERC20Metadata(token).decimals(), IERC20Metadata(token).decimals());
        }

        address feed = aggregators[token];
        address registeredBase = baseTokens[token];

        if (feed == address(0) || registeredBase != baseToken) {
            return (0, 0);
        }

        (, int256 answer, , , ) = AggregatorV3Interface(feed).latestRoundData();
        if (answer <= 0) return (0, 0);

        uint8 feedDecimals = AggregatorV3Interface(feed).decimals();
        return (uint256(answer), feedDecimals);
    }

    /// @notice Convert amount from one token to another
    /// @param fromToken Token to convert from
    /// @param toToken Token to convert to
    /// @param amount Amount to convert
    /// @return convertedAmount Amount in target token
    function convertAmount(address fromToken, address toToken, uint256 amount) external view returns (uint256 convertedAmount) {
        // Если токены совпадают, возвращаем исходную сумму
        if (fromToken == toToken) {
            return amount;
        }

        // Получаем цены токенов в USD
        (uint256 fromPrice, uint8 fromDecimals) = this.getPrice(fromToken, baseTokens[fromToken]);
        (uint256 toPrice, uint8 toDecimals) = this.getPrice(toToken, baseTokens[toToken]);

        if (fromPrice == 0 || toPrice == 0) {
            return 0;
        }

        // Получаем информацию о десятичных знаках токенов
        uint8 fromTokenDecimals = IERC20Metadata(fromToken).decimals();
        uint8 toTokenDecimals = IERC20Metadata(toToken).decimals();

        // Рассчитываем сумму в целевом токене
        // 1. Конвертируем в базовую сумму
        uint256 baseAmount = (amount * fromPrice) / (10**fromDecimals);
        // 2. Конвертируем из базовой суммы в целевой токен
        uint256 adjustedAmount = (baseAmount * (10**toTokenDecimals)) / (10**fromTokenDecimals);
        // 3. Конвертируем из базовой в токен назначения
        convertedAmount = (adjustedAmount * (10**toDecimals)) / toPrice;

        return convertedAmount;
    }

    /// @notice Check if a token pair is supported
    /// @param token Token to check
    /// @param baseToken Base token to check against
    /// @return supported True if the pair is supported
    function isPairSupported(address token, address baseToken) external view returns (bool supported) {
        // Если токены совпадают, пара всегда поддерживается
        if (token == baseToken) {
            return true;
        }

        address feed = aggregators[token];
        address registeredBase = baseTokens[token];

        // Поддерживается, если есть агрегатор и базовый токен совпадает
        return (feed != address(0) && registeredBase == baseToken);
    }
}
