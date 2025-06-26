// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Prize type: monetary (ERC-20) or promo (offline code)
enum PrizeType {
    MONETARY,
    PROMO
}

/// @notice Description of a single prize slot
struct PrizeInfo {
    PrizeType prizeType; // prize type
    address token; // ERC-20 token address (for MONETARY)
    uint256 amount; // token amount (for MONETARY)
    uint8 distribution; // distribution scheme (0 = flat, 1 = descending)
    string uri; // description/URI for non-monetary prizes
}
