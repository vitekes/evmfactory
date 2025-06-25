# Contest Module V2

This document summarizes the design for version 2 of the contest module.

## Overview

The module consists of a factory responsible only for deployment and receiving funds, and an escrow contract that manages prize storage and payouts. Auxiliary plugins such as `Validator`, `NFTManager` and `EventRouter` can be replaced via the `Registry` without redeploying contests.

## Factory

```solidity
/// @dev Deploys a new contest escrow. Reverts ContestFundingMissing or InvalidPrizeData.
function createContest(PrizeInfo[] calldata prizes, bytes calldata metadata) external returns (address escrow);

function registry() external view returns (address);
function setRegistry(address newRegistry) external; // GOVERNOR

function feeManager() external view returns (address);
function setFeeManager(address mgr) external; // GOVERNOR
```

## Escrow

```solidity
constructor(
    address _creator,
    PrizeInfo[] memory _prizes,
    address _registry,
    uint256 _gasPool,
    address _commissionToken
);

/// @notice Distributes all prizes to winners once.
/// @dev Reverts WrongWinnersCount or ContestAlreadyFinalized.
function finalize(address[] calldata winners) external;

/// @notice Cancel the contest before finalization.
function cancel() external; // only creator

function creator() external view returns (address);
function finalized() external view returns (bool);

function prizes(uint256 index) external view returns (PrizeInfo memory);
function prizesLength() external view returns (uint256);

function winners(uint256 index) external view returns (address);
function winnersLength() external view returns (uint256);

function gasPool() external view returns (uint256);
```

## Plugins

- **Validator** — checks every prize, allowed tokens and distribution rules.
- **EventRouter** — optionally relays escrow events to subscribers.
- **NFTManager** — mints NFTs for winners.

## Data Structures and Errors

```solidity
struct PrizeInfo {
    uint8   prizeType;    // 0 = MONETARY, 1 = PROMO
    address token;        // address(0) = ETH
    uint256 amount;       // 0 for PROMO
    uint8   distribution; // 0 = fixed, 1 = descending N%, ...
    string  uri;          // off-chain CID
}

error InvalidPrizeData();
error ContestFundingMissing();
error ContestAlreadyFinalized();
error WrongWinnersCount();
```

## Improvements in V2

- **Fail-fast** — missing token transfers are caught during `createContest`.
- **Minimal surface** — no `transferFrom` calls after deployment and no external calls before `finalized`.
- **Modular** — services like `NFTManager` can be updated in the registry.
- **Gas optimized** — prizes array written once, payouts batched by `maxWinnersPerTx`.
- **Stable events** — each prize index is deterministic, easing indexing.
- **Backwards compatibility** — previous structures and events remain valid.
