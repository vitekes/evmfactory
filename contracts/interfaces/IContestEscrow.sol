// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {PrizeInfo} from '../modules/contests/shared/PrizeInfo.sol';

interface IContestEscrow {
    function addPrizes(PrizeInfo[] calldata prizes) external;
    function finalize(address[] calldata winners) external;
}
