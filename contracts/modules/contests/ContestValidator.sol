// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../../core/CoreSystem.sol';
import '../../errors/Errors.sol';
import '../../payments/interfaces/ITokenValidator.sol';
import './interfaces/IContestValidator.sol';
import './shared/PrizeInfo.sol';
import '../../core/CoreDefs.sol';

/// @title ContestValidator
/// @notice Basic validator for Contest prizes
contract ContestValidator is IContestValidator {
    CoreSystem public immutable core;
    ITokenValidator public tokenValidator;

    constructor(address _core, address _tokenValidator) {
        // Check for zero addresses during initialization
        if (_core == address(0) || _tokenValidator == address(0)) revert ZeroAddress();

        // Initialize immutable variable
        core = CoreSystem(_core);
        tokenValidator = ITokenValidator(_tokenValidator);
    }

    modifier onlyGovernor() {
        if (!core.hasRole(CoreDefs.GOVERNOR_ROLE, msg.sender)) revert NotGovernor();
        _;
    }

    event TokenValidatorUpdated(address oldValidator, address newValidator);

    function setTokenValidator(address newValidator) external onlyGovernor {
        if (newValidator == address(0)) revert ZeroAddress();
        address oldValidator = address(tokenValidator);
        tokenValidator = ITokenValidator(newValidator);
        emit TokenValidatorUpdated(oldValidator, newValidator);
    }

    // --- IContestValidator ---

    function validatePrize(PrizeInfo calldata prize) external view override {
        // Check prize type validity before other checks
        if (uint8(prize.prizeType) > 1) {
            revert InvalidPrizeData_UnsupportedType();
        }

        // Cache prize type to reduce calldata access
        PrizeType prizeType = prize.prizeType;

        // Structure checks from cheap to expensive to optimize gas
        if (prizeType == PrizeType.MONETARY) {
            // Check for zero token address
            if (prize.token == address(0)) revert InvalidPrizeData();

            // Check cheapest conditions first
            if (prize.amount == 0) revert InvalidPrizeData_ZeroAmount();

            // Then check token allowance
            if (!isTokenAllowed(prize.token)) revert NotAllowedToken();

            // Finally, check distribution validity
            if (!isDistributionValid(prize.amount, prize.distribution)) revert InvalidDistribution();
        } else if (prizeType == PrizeType.PROMO) {
            // Use bitwise OR to check multiple conditions simultaneously
            // This allows checking in a single operation
            if ((prize.amount | uint160(prize.token)) != 0) revert InvalidPrizeData_InvalidPromoSettings();
        }
    }

    function isTokenAllowed(address token) public view override returns (bool) {
        return tokenValidator.isTokenAllowed(token);
    }

    /// @notice Checks validity of prize distribution scheme
    /// @dev Supported distribution schemes:
    ///   - 0: Fixed amount (same for all)
    ///   - 1: Decreasing amount (proportional to ranking position)
    /// @param amount Total prize amount
    /// @param distribution Distribution scheme code
    /// @return Validity of distribution scheme
    function isDistributionValid(uint256 amount, uint8 distribution) public pure override returns (bool) {
        // Check that prize amount is not zero
        if (amount == 0) return false;

        // Type 0: Fixed amount (same for all)
        if (distribution == 0) return true;

        // Type 1: Decreasing amount (proportional to ranking position)
        if (distribution == 1) return true;

        // Other types not supported
        return false;
    }
}
