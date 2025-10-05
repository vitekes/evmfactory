// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../shared/PrizeInfo.sol';

/// @notice Validator plugin for Contests that verifies prize configurations
interface IContestValidator {
    /// @notice Validates a single prize slot configuration
    /// @dev Reverts with specific error on validation failure
    /// @param prize Prize information structure to validate
    function validatePrize(PrizeInfo calldata prize) external view;

    /// @notice Checks if a token is allowed for prizes
    /// @param token Token address to check
    /// @return True if token is allowed, false otherwise
    function isTokenAllowed(address token) external view returns (bool);

    /// @notice Validates if a distribution scheme is valid for the given amount
    /// @param amount Total prize amount
    /// @param distribution Distribution scheme identifier
    /// @return True if distribution is valid, false otherwise
    function isDistributionValid(uint256 amount, uint8 distribution) external view returns (bool);
}
