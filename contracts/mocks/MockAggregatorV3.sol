// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../interfaces/AggregatorV3Interface.sol';

/// @title Mock Chainlink Aggregator V3
/// @notice Mock implementation of AggregatorV3Interface for testing
contract MockAggregatorV3 is AggregatorV3Interface {
    uint8 private _decimals;
    int256 private _answer;
    uint256 private _timestamp;
    uint80 private _roundId;

    constructor(uint8 decimals_) {
        _decimals = decimals_;
        _timestamp = block.timestamp;
        _roundId = 1;
    }

    function setLatestAnswer(int256 answer) external {
        _answer = answer;
        _timestamp = block.timestamp;
        _roundId++;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external pure override returns (string memory) {
        return 'Mock Price Feed';
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(
        uint80 _id
    )
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        require(_id <= _roundId, 'No data present');

        // For simplicity, return the latest data for any valid round ID
        return (_id, _answer, _timestamp, _timestamp, _id);
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, _answer, _timestamp, _timestamp, _roundId);
    }
}
