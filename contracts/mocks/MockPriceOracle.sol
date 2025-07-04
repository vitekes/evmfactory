// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../interfaces/IPriceOracle.sol';

// Error declarations if not defined in imported interfaces
error UnsupportedPair();
error InvalidPrice();
error Overflow();

/// @title MockPriceOracle
/// @notice Test price oracle for modular testing
/// @dev Used only for testing, not for production use
contract MockPriceOracle is IPriceOracle {
    // Mapping of token prices relative to base token
    mapping(address => uint256) public tokenPrices;
    mapping(address => uint8) public tokenDecimals;

    // Mapping of supported token pairs
    mapping(address => mapping(address => bool)) public supportedPairs;

    constructor() {
        // Default support for ETH conversion with both sentinel values
        address eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        tokenPrices[eth] = 1 ether; // 1 ETH = 1 ETH (base price)
        tokenDecimals[eth] = 18;

        // Also support zero address as native currency
        tokenPrices[address(0)] = 1 ether;
        tokenDecimals[address(0)] = 18;

        // Ensure pair support between both ETH sentinel values
        supportedPairs[eth][address(0)] = true;
        supportedPairs[address(0)][eth] = true;
    }

    /// @notice Sets token price
    /// @param token Token address
    /// @param priceInWei Price in wei
    /// @param decimals Number of token decimals
    function setTokenPrice(address token, uint256 priceInWei, uint8 decimals) external {
        require(token != address(0), 'Zero address not allowed');
        require(priceInWei > 0, 'Price must be positive');
        require(decimals <= 18, 'Decimals must be <= 18'); // Common limit for most ERC20 tokens

        tokenPrices[token] = priceInWei;
        tokenDecimals[token] = decimals;
    }

    /// @notice Sets support for a token pair
    /// @param baseToken Base token
    /// @param paymentToken Payment token
    /// @param supported Support flag
    function setPairSupport(address baseToken, address paymentToken, bool supported) external {
        require(baseToken != address(0), 'Base token cannot be zero address');
        require(paymentToken != address(0), 'Payment token cannot be zero address');
        require(baseToken != paymentToken, 'Tokens must be different');

        supportedPairs[baseToken][paymentToken] = supported;
        supportedPairs[paymentToken][baseToken] = supported;
    }

    /// @notice Checks if token pair is supported
    /// @param baseToken Base token
    /// @param paymentToken Payment token
    /// @return supported Whether the pair is supported
    function isPairSupported(address baseToken, address paymentToken) external view returns (bool) {
        // Handle ETH sentinel values
        address eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

        // Normalize addresses - treat address(0) as ETH_SENTINEL
        address normalizedBase = baseToken == address(0) ? eth : baseToken;
        address normalizedPayment = paymentToken == address(0) ? eth : paymentToken;

        // Check if tokens are identical after normalization
        if (normalizedBase == normalizedPayment) {
            return true;
        }

        // Check the mapping with normalized addresses
        return supportedPairs[normalizedBase][normalizedPayment];
    }

    /// @notice Gets token price relative to base token
    /// @param token Token address
    /// @param baseToken Base token address
    /// @return price Token price
    /// @return decimals Number of decimals
    function getPrice(address token, address baseToken) external view returns (uint256 price, uint8 decimals) {
        // If tokens are identical, return 1:1
        if (token == baseToken) {
            return (10 ** uint256(tokenDecimals[token]), tokenDecimals[token]);
        }

        // Check if price exists for token
        if (tokenPrices[token] == 0) revert InvalidPrice();

        return (tokenPrices[token], tokenDecimals[token]);
    }

    /// @notice Converts amount from one token to another
    /// @param baseToken Source token
    /// @param paymentToken Target token
    /// @param baseAmount Amount in source token
    /// @return paymentAmount Equivalent amount in target token
    function convertAmount(
        address baseToken,
        address paymentToken,
        uint256 baseAmount
    ) external view returns (uint256 paymentAmount) {
        // Handle zero amount early
        if (baseAmount == 0) {
            return 0;
        }

        // Handle ETH sentinel values
        address eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

        // Normalize addresses - treat address(0) as ETH_SENTINEL
        address normalizedBase = baseToken == address(0) ? eth : baseToken;
        address normalizedPayment = paymentToken == address(0) ? eth : paymentToken;

        // Check if tokens are identical after normalization
        if (normalizedBase == normalizedPayment) {
            return baseAmount;
        }

        // Check pair support with specific error
        if (!supportedPairs[normalizedBase][normalizedPayment]) {
            revert UnsupportedPair();
        }

        // Cache storage values to save gas
        uint256 basePrice = tokenPrices[normalizedBase];
        uint256 paymentPrice = tokenPrices[normalizedPayment];

        // Check price validity with detailed error
        if (basePrice == 0) revert InvalidPrice();
        if (paymentPrice == 0) revert InvalidPrice();

        // Protection against overflow when multiplying large numbers
        // Use check before calculation
        if (baseAmount > 0 && basePrice > type(uint256).max / baseAmount) {
            revert Overflow();
        }

        // Safe calculation with zero division check
        return (baseAmount * basePrice) / paymentPrice;
    }
}
