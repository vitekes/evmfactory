// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../interfaces/IPriceOracle.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';

/// @notice Mock price oracle for testing
contract MockPriceFeed is IPriceOracle {
    // Маппинг токен => цена (в базовой валюте)
    mapping(address => uint256) public prices;
    // Маппинг (токен + базовый токен) => поддерживается ли пара
    mapping(address => mapping(address => bool)) public supportedPairs;
    // Маппинг токен => базовый токен
    mapping(address => address) public baseTokens;
    // Маппинг токен => количество десятичных знаков в цене
    mapping(address => uint8) public priceDecimals;

    /// @notice Установить цену для токена
    /// @param token Токен
    /// @param price Цена
    /// @param baseToken Базовый токен для сравнения
    /// @param decimals Количество десятичных знаков в цене
    function setPrice(address token, uint256 price, address baseToken, uint8 decimals) external {
        prices[token] = price;
        baseTokens[token] = baseToken;
        supportedPairs[token][baseToken] = true;
        priceDecimals[token] = decimals;
    }

    /// @notice Получить цену в USD (устаревший метод, для обратной совместимости)
    function tokenPriceUsd(address token) external view returns (uint256) {
        return prices[token];
    }

    /// @notice Get price for a token pair
    /// @param token Token to get price for
    /// @param baseToken Base token to compare against
    /// @return price Price with decimals
    /// @return decimals Number of decimals in the price
    function getPrice(address token, address baseToken) external view returns (uint256 price, uint8 decimals) {
        // Если токены совпадают, возвращаем 1:1
        if (token == baseToken) {
            return (10 ** IERC20Metadata(token).decimals(), IERC20Metadata(token).decimals());
        }

        // Проверяем поддержку пары
        if (!supportedPairs[token][baseToken]) {
            return (0, 0);
        }

        return (prices[token], priceDecimals[token]);
    }

    /// @notice Convert amount from one token to another
    /// @param fromToken Token to convert from
    /// @param toToken Token to convert to
    /// @param amount Amount to convert
    /// @return convertedAmount Amount in target token
    function convertAmount(
        address fromToken,
        address toToken,
        uint256 amount
    ) external view returns (uint256 convertedAmount) {
        // Если токены совпадают, возвращаем исходную сумму
        if (fromToken == toToken) {
            return amount;
        }

        // Проверяем поддержку пар
        if (!supportedPairs[fromToken][baseTokens[fromToken]] || !supportedPairs[toToken][baseTokens[toToken]]) {
            return 0;
        }

        // Получаем цены
        uint256 fromPrice = prices[fromToken];
        uint256 toPrice = prices[toToken];
        uint8 fromPriceDecimals = priceDecimals[fromToken];
        uint8 toPriceDecimals = priceDecimals[toToken];

        if (fromPrice == 0 || toPrice == 0) {
            return 0;
        }

        // Получаем информацию о десятичных знаках токенов
        uint8 fromTokenDecimals = IERC20Metadata(fromToken).decimals();
        uint8 toTokenDecimals = IERC20Metadata(toToken).decimals();

        // Конвертируем сумму
        // 1. Преобразуем в базовую сумму
        uint256 baseAmount = (amount * fromPrice) / (10 ** fromPriceDecimals);
        // 2. Корректируем десятичные знаки
        uint256 adjustedAmount = (baseAmount * (10 ** toTokenDecimals)) / (10 ** fromTokenDecimals);
        // 3. Конвертируем в целевой токен
        convertedAmount = (adjustedAmount * (10 ** toPriceDecimals)) / toPrice;

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

        return supportedPairs[token][baseToken];
    }
}
