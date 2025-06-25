// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../shared/PrizeInfo.sol';

/// @notice Validator plugin for Contests
interface IContestValidator {
    /// @dev Validate a single prize slot. Revert on violation.
    function validatePrize(PrizeInfo calldata prize) external view;

    /// @dev Whether a token is allowed for prizes
    function isTokenAllowed(address token) external view returns (bool);

    /// @dev Whether a distribution scheme is valid for the amount
    function isDistributionValid(uint256 amount, uint8 distribution) external view returns (bool);
}
