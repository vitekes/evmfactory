// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './interfaces/IPriceOracle.sol';
import '../core/interfaces/ICoreSystem.sol';
import '../external/AggregatorV3Interface.sol';
import '../errors/Errors.sol';
import '../lib/Native.sol';
import '../shared/CoreDefs.sol';

contract ChainlinkPriceOracle is IPriceOracle {
    /// Константа DEFAULT_ADMIN_ROLE из AccessControl
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    ICoreSystem public immutable core;

    // Mapping: token => USD price feed address
    mapping(address => address) public priceFeeds;

    // ETH address for referencing native currency
    address public constant ETH_ADDRESS = Native.ETH_ADDRESS;

    // Stablecoin addresses for direct conversions
    mapping(address => bool) public stablecoins;

    // Number of decimals in price feed responses
    uint8 public constant FEED_DECIMALS = 8;

    event PriceFeedSet(address indexed token, address indexed priceFeed);
    event StablecoinSet(address indexed token, bool status);

    constructor(address _core) {
        if (_core == address(0)) revert ZeroAddress();
        core = ICoreSystem(_core);
    }

    modifier onlyOperator() {
        if (!core.hasRole(CoreDefs.OPERATOR_ROLE, msg.sender)) 
            revert NotOperator();
        _;
    }

    modifier onlyAdmin() {
        if (!core.hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) 
            revert NotAdmin();
        _;
    }

    /// @notice Set price feed for a token
    /// @param token Token address
    /// @param priceFeed Chainlink price feed address
    function setPriceFeed(address token, address priceFeed) external onlyOperator {
        if (token == address(0)) revert ZeroAddress();

        // Allow clearing a price feed
        if (priceFeed != address(0)) {
            // Verify this is actually a price feed
            try AggregatorV3Interface(priceFeed).decimals() returns (uint8 decimals) {
                if (decimals != FEED_DECIMALS) revert InvalidDecimals();
            } catch {
                revert InvalidPriceFeed();
            }
        }

        priceFeeds[token] = priceFeed;
        emit PriceFeedSet(token, priceFeed);
    }

    /// @notice Set or unset a token as a stablecoin
    /// @param token Token address
    /// @param isStable Whether the token is a stablecoin
    function setStablecoin(address token, bool isStable) external onlyOperator {
        if (token == address(0)) revert ZeroAddress();
        stablecoins[token] = isStable;
        emit StablecoinSet(token, isStable);
    }

    /// @notice Convert amount from one token to another
    /// @param baseToken Base token address
    /// @param quoteToken Quote token address
    /// @param amount Amount to convert
    /// @return The amount in quote token
    function convertAmount(
        address baseToken,
        address quoteToken,
        uint256 amount
    ) external view returns (uint256) {
        if (amount == 0) return 0;
        if (baseToken == quoteToken) return amount;

        // For stablecoin to stablecoin conversions, use 1:1 ratio
        if (stablecoins[baseToken] && stablecoins[quoteToken]) {
            return _adjustDecimals(amount, baseToken, quoteToken);
        }

        // Get price feeds
        address baseFeed = priceFeeds[baseToken];
        address quoteFeed = priceFeeds[quoteToken];

        if (baseFeed == address(0) || quoteFeed == address(0)) {
            revert PriceFeedNotFound();
        }

        // Get price data
        int256 basePrice = _getPrice(baseFeed);
        int256 quotePrice = _getPrice(quoteFeed);

        if (basePrice <= 0 || quotePrice <= 0) {
            revert InvalidPrice();
        }

        // Calculate conversion: (amount * basePrice / quotePrice) adjusted for decimals
        uint256 valueInUSD = (amount * uint256(basePrice)) / 10**uint256(FEED_DECIMALS);
        uint256 convertedAmount = (valueInUSD * 10**uint256(FEED_DECIMALS)) / uint256(quotePrice);

        // Adjust for token decimals
        return _adjustDecimals(convertedAmount, baseToken, quoteToken);
    }

    /// @notice Check if pair is supported by oracle
    /// @param baseToken Base token address
    /// @param quoteToken Quote token address
    /// @return supported Whether the pair is supported
    function isPairSupported(address baseToken, address quoteToken) external view returns (bool) {
        if (baseToken == quoteToken) return true;

        // Stablecoin to stablecoin is always supported
        if (stablecoins[baseToken] && stablecoins[quoteToken]) return true;

        // Otherwise both tokens need price feeds
        return priceFeeds[baseToken] != address(0) && priceFeeds[quoteToken] != address(0);
    }

    /// @dev Gets the latest price from a Chainlink feed
    /// @param priceFeed Address of the price feed
    /// @return price The latest price
    function _getPrice(address priceFeed) internal view returns (int256 price) {
        (, price, , , ) = AggregatorV3Interface(priceFeed).latestRoundData();
    }

    /// @dev Adjusts amount for decimal differences between tokens
    /// @param amount Amount to adjust
    /// @param fromToken From token address
    /// @param toToken To token address
    /// @return Adjusted amount
    function _adjustDecimals(
        uint256 amount,
        address fromToken,
        address toToken
    ) internal pure returns (uint256) {
        uint8 fromDecimals = _getDecimals(fromToken);
        uint8 toDecimals = _getDecimals(toToken);

        if (fromDecimals == toDecimals) return amount;

        if (fromDecimals > toDecimals) {
            // Scale down
            return amount / (10**(fromDecimals - toDecimals));
        } else {
            // Scale up
            return amount * (10**(toDecimals - fromDecimals));
        }
    }

    /// @dev Gets the number of decimals for a token
    /// @param token Token address (use ETH_ADDRESS for ETH)
    /// @return Number of decimals
    function _getDecimals(address token) internal pure returns (uint8) {
        // Native ETH has 18 decimals
        if (token == address(0) || token == ETH_ADDRESS) return 18;

        // For this example we'll assume all ERC20 tokens have 18 decimals
        // In a real implementation, you would call the decimals() function on the token
        return 18;
    }
}
