// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../interfaces/IPriceFeed.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title ChainlinkPriceFeed
/// @notice Reads USD price from Chainlink feeds
contract ChainlinkPriceFeed is IPriceFeed {
    mapping(address => address) public aggregators;

    function setAggregator(address token, address feed) external {
        aggregators[token] = feed;
    }

    function tokenPriceUsd(address token) external view returns (uint256) {
        address feed = aggregators[token];
        if (feed == address(0)) return 0;
        (, int256 answer,, ,) = AggregatorV3Interface(feed).latestRoundData();
        uint8 decimals = AggregatorV3Interface(feed).decimals();
        if (answer <= 0) return 0;
        return uint256(answer) * (10 ** (18 - decimals));
    }
}
