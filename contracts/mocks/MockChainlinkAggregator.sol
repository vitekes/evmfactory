// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../interfaces/AggregatorV3Interface.sol';

/// @title MockChainlinkAggregator
/// @notice Mock for Chainlink's AggregatorV3Interface for testing
contract MockChainlinkAggregator is AggregatorV3Interface {
    uint8 private _decimals;
    string private _description;
    uint256 private _version;
    int256 private _answer;
    uint256 private _timestamp;
    uint80 private _roundId;

    constructor(
        uint8 decimals_,
        string memory description_,
        int256 initialAnswer
    ) {
        _decimals = decimals_;
        _description = description_;
        _version = 1;
        _answer = initialAnswer;
        _timestamp = block.timestamp;
        _roundId = 1;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external view override returns (string memory) {
        return _description;
    }

    function version() external view override returns (uint256) {
        return _version;
    }

    function getRoundData(uint80 roundIdParam) external view override returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (roundIdParam, _answer, _timestamp, _timestamp, roundIdParam);
    }

    function latestRoundData() external view override returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (_roundId, _answer, _timestamp, _timestamp, _roundId);
    }

    // Дополнительные функции для тестирования

    function updateAnswer(int256 newAnswer) external {
        _answer = newAnswer;
        _timestamp = block.timestamp;
        _roundId++;
    }

    function updateRoundData(
        uint80 roundId,
        int256 answer,
        uint256 timestamp
    ) external {
        _roundId = roundId;
        _answer = answer;
        _timestamp = timestamp;
    }
}
