// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IContestValidator} from '../modules/contests/interfaces/IContestValidator.sol';
import {PrizeInfo} from '../modules/contests/shared/PrizeInfo.sol';

/// @notice Minimal validator used in tests to mimic a permissive contest validator
contract ContestValidatorMock is IContestValidator {
    bool private revertOnValidate;

    constructor(bool _revertOnValidate) {
        revertOnValidate = _revertOnValidate;
    }

    function setRevertOnValidate(bool value) external {
        revertOnValidate = value;
    }

    function validatePrize(PrizeInfo calldata) external view override {
        if (revertOnValidate) {
            revert('validatePrize revert');
        }
    }

    function isTokenAllowed(address) external pure override returns (bool) {
        return true;
    }

    function isDistributionValid(uint256, uint8) external pure override returns (bool) {
        return true;
    }
}
