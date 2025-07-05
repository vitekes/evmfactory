// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../interfaces/IPriceOracle.sol";

/// @title Mock price oracle for demos
contract MockPriceOracle is IPriceOracle {
    mapping(address => mapping(address => uint256)) public rates;

    function setRate(address token, address baseToken, uint256 rate) external {
        rates[token][baseToken] = rate;
    }

    function getPrice(address token, address baseToken) external view override returns (uint256 price, uint8 decimals) {
        price = rates[token][baseToken];
        decimals = 18;
    }

    function convertAmount(address fromToken, address toToken, uint256 amount) external view override returns (uint256 convertedAmount) {
        if (fromToken == toToken) return amount;
        uint256 rate = rates[fromToken][toToken];
        return (amount * rate) / 1e18;
    }

    function isPairSupported(address token, address baseToken) external view override returns (bool supported) {
        return rates[token][baseToken] > 0;
    }
}
