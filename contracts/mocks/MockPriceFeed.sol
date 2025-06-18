// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../interfaces/IPriceFeed.sol";

contract MockPriceFeed is IPriceFeed {
    mapping(address => uint256) public prices;

    function setPrice(address token, uint256 price) external {
        prices[token] = price;
    }

    function tokenPriceUsd(address token) external view returns (uint256) {
        return prices[token];
    }
}
