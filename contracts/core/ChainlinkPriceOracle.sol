// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../interfaces/IPriceOracle.sol';
import '../interfaces/AggregatorV3Interface.sol';
import '../core/AccessControlCenter.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '../errors/Errors.sol';

/// @title Chainlink Price Oracle
/// @notice Simple price oracle using Chainlink feeds
contract ChainlinkPriceOracle is IPriceOracle {
    /// @notice Access control contract
    AccessControlCenter public immutable accessControl;

    /// @notice Maximum allowed price age in seconds
    uint256 public constant MAX_PRICE_AGE = 24 hours;

    /// @notice Chainlink price feed address for each token
    mapping(address => address) public priceFeeds;

    /// @notice Base token for each price feed
    mapping(address => address) public baseTokens;

    /// @notice Oracle constructor
    /// @param _accessControl Address of AccessControlCenter
    constructor(address _accessControl) {
        if (_accessControl == address(0)) revert InvalidAddress();
        accessControl = AccessControlCenter(_accessControl);
    }

    /// @notice Set the price feed for a token
    /// @param token Token address
    /// @param priceFeed Chainlink feed address
    /// @param baseToken Base token address (e.g. USDC for USD feeds)
    function setPriceFeed(address token, address priceFeed, address baseToken) external {
        if (!accessControl.hasRole(accessControl.GOVERNOR_ROLE(), msg.sender)) revert NotGovernor();
        if (token == address(0) || priceFeed == address(0) || baseToken == address(0)) revert InvalidAddress();

        priceFeeds[token] = priceFeed;
        baseTokens[token] = baseToken;
    }

    /// @notice Get price for a token pair
    /// @param token Token to quote
    /// @param baseToken Base token for comparison
    /// @return price Price with decimals
    /// @return decimals Number of decimals in the price
    function getPrice(address token, address baseToken) public view override returns (uint256 price, uint8 decimals) {
        // Shortcut for identical tokens
        if (token == baseToken) {
            return (10 ** IERC20Metadata(token).decimals(), IERC20Metadata(token).decimals());
        }

        // Check for direct feed
        address directFeed = priceFeeds[token];
        address directBase = baseTokens[token];

        // Validate pair support
        if (directFeed == address(0) || directBase != baseToken) revert UnsupportedPair();

        // Get data from Chainlink
        AggregatorV3Interface feed = AggregatorV3Interface(directFeed);
        (uint80 roundId, int256 answer, , uint256 updatedAt, uint80 answeredInRound) = feed.latestRoundData();

        // Verify data validity
        if (answer <= 0) revert InvalidPrice();
        if (updatedAt < block.timestamp - MAX_PRICE_AGE) revert StalePrice();
        if (answeredInRound < roundId) revert StalePrice();

        return (uint256(answer), feed.decimals());
    }

    /// @notice Convert amount from one token to another
    /// @param fromToken Source token
    /// @param toToken Target token
    /// @param amount Amount to convert
    /// @return convertedAmount Amount in target token
    function convertAmount(
        address fromToken,
        address toToken,
        uint256 amount
    ) public view override returns (uint256 convertedAmount) {
        // Shortcut for identical tokens
        if (fromToken == toToken) return amount;

        // Get common base token
        address fromBase = baseTokens[fromToken];
        address toBase = baseTokens[toToken];

        // Validate base token compatibility
        if (fromBase == address(0) || toBase == address(0) || fromBase != toBase) revert UnsupportedPair();

        // Fetch prices and decimals
        (uint256 fromPrice, uint8 fromDecimals) = getPrice(fromToken, fromBase);
        (uint256 toPrice, uint8 toDecimals) = getPrice(toToken, fromBase);
        uint8 fromTokenDecimals = IERC20Metadata(fromToken).decimals();
        uint8 toTokenDecimals = IERC20Metadata(toToken).decimals();

        // Convert through base token
        uint256 baseAmount = (amount * fromPrice) / (10 ** fromDecimals);
        uint256 adjustedForDecimals = (baseAmount * (10 ** toTokenDecimals)) / (10 ** fromTokenDecimals);
        return (adjustedForDecimals * (10 ** toDecimals)) / toPrice;
    }

    /// @notice Check if a token pair is supported
    /// @param token Token to check
    /// @param baseToken Base token to check against
    /// @return supported True if the pair is supported
    function isPairSupported(address token, address baseToken) external view override returns (bool) {
        if (token == baseToken) return true;
        address feed = priceFeeds[token];
        address tokenBase = baseTokens[token];
        return feed != address(0) && tokenBase == baseToken;
    }

    /// @notice Extended conversion with a fallback via an intermediate token
    /// @param fromToken Source token
    /// @param toToken Target token
    /// @param intermediateToken Intermediate token for conversion
    /// @param amount Amount to convert
    /// @return Amount in the target token
    function convertAmountWithIntermediateToken(
        address fromToken,
        address toToken,
        address intermediateToken,
        uint256 amount
    ) external view returns (uint256) {
        // Shortcut for identical tokens
        if (fromToken == toToken) return amount;

        // Validate intermediate token
        if (intermediateToken == address(0)) revert InvalidAddress();

        // Try direct conversion first
        try this.convertAmount(fromToken, toToken, amount) returns (uint256 result) {
            return result;
        } catch {
            // Fallback to intermediate token
            return _convertViaIntermediateToken(fromToken, toToken, intermediateToken, amount);
        }
    }

    /// @dev Helper to convert via an intermediate token
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
