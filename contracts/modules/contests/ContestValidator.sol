// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../../core/AccessControlCenter.sol';
import '../../interfaces/core/IMultiValidator.sol';
import '../../errors/Errors.sol';
import './shared/PrizeInfo.sol';
import './interfaces/IContestValidator.sol';

/// @title ContestValidator
/// @notice Basic validator for Contest prizes
contract ContestValidator is IContestValidator {
    AccessControlCenter public access;
    IMultiValidator public tokenValidator;

    constructor(address _access, address _tokenValidator) {
        access = AccessControlCenter(_access);
        tokenValidator = IMultiValidator(_tokenValidator);
    }

    modifier onlyGovernor() {
        if (!access.hasRole(access.GOVERNOR_ROLE(), msg.sender)) revert NotGovernor();
        _;
    }

    function setTokenValidator(address newValidator) external onlyGovernor {
        if (newValidator == address(0)) revert ZeroAddress();
        tokenValidator = IMultiValidator(newValidator);
    }

    // --- IContestValidator ---

    function validatePrize(PrizeInfo calldata prize) external view override {
        if (prize.prizeType == PrizeType.MONETARY) {
            if (prize.amount == 0) revert InvalidPrizeData();
            if (!isTokenAllowed(prize.token)) revert NotAllowedToken();
            if (!isDistributionValid(prize.amount, prize.distribution)) revert InvalidDistribution();
        } else if (prize.prizeType == PrizeType.PROMO) {
            if (prize.amount != 0 || prize.token != address(0)) revert InvalidPrizeData();
        } else {
            revert InvalidPrizeData();
        }
    }

    function isTokenAllowed(address token) public view override returns (bool) {
        return tokenValidator.isAllowed(token);
    }

    function isDistributionValid(uint256 amount, uint8 distribution) public pure override returns (bool) {
        if (distribution == 0) {
            return amount > 0;
        }
        if (distribution == 1) {
            return amount > 0;
        }
        return false;
    }
}
