// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {ContestEscrow} from "contracts/modules/contests/ContestEscrow.sol";
import {PrizeInfo, PrizeType} from "contracts/modules/contests/shared/PrizeInfo.sol";
import {Registry} from "contracts/core/Registry.sol";
import {MockAccessControlCenter} from "contracts/mocks/MockAccessControlCenter.sol";
import {TestToken} from "contracts/mocks/TestToken.sol";

contract ContestEscrowFeeInvariantTest is Test {
    Registry registry;
    MockAccessControlCenter acc;
    TestToken token;

    bytes32 constant MODULE_ID = keccak256("Contest");

    function setUp() public {
        acc = new MockAccessControlCenter();
        registry = new Registry();
        registry.initialize(address(acc));
        registry.registerFeature(MODULE_ID, address(1), 0);
        token = new TestToken("T", "T");
    }

    function helper_totalPaidEqualsInput(uint8 count, uint96[5] memory amounts, uint8[5] memory dist, uint256 seed) public {
        count = uint8(bound(count, 1, 5));
        PrizeInfo[] memory prizes = new PrizeInfo[](count);
        address[] memory winners = new address[](count);
        uint256 total;
        for (uint8 i = 0; i < count; i++) {
            uint256 amt = uint256(amounts[i]) % 1e18 + 1;
            prizes[i] = PrizeInfo({
                prizeType: PrizeType.MONETARY,
                token: address(token),
                amount: amt,
                distribution: dist[i] % 2,
                uri: ""
            });
            winners[i] = address(uint160(uint256(keccak256(abi.encode(seed, i)))));
            total += amt;
        }

        ContestEscrow esc = new ContestEscrow(
            registry,
            address(this),
            prizes,
            address(token),
            0,
            0,
            new address[](0),
            ""
        );
        token.transfer(address(esc), total);

        uint256[] memory beforeBal = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            beforeBal[i] = token.balanceOf(winners[i]);
        }

        esc.finalize(winners);

        uint256 paid;
        for (uint256 i = 0; i < count; i++) {
            paid += token.balanceOf(winners[i]) - beforeBal[i];
        }

        assertEq(paid, total, "paid != input");
        assertEq(token.balanceOf(address(esc)), 0, "escrow not empty");
    }
}
