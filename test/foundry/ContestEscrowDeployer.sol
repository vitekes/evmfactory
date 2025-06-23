// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Registry} from "contracts/core/Registry.sol";
import {ContestEscrow} from "contracts/modules/contests/ContestEscrow.sol";
import {PrizeInfo} from "contracts/modules/contests/shared/PrizeInfo.sol";

contract ContestEscrowDeployer {
    function deploy(
        Registry registry,
        address creator,
        PrizeInfo[] memory prizes,
        address commissionToken,
        uint256 commissionFee,
        uint256 gasPool
    ) external returns (ContestEscrow esc) {
        address[] memory judges = new address[](0);
        esc = new ContestEscrow(
            registry,
            creator,
            prizes,
            commissionToken,
            commissionFee,
            gasPool,
            judges,
            ""
        );
    }
}
