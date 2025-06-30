// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {ContestEscrow} from "contracts/modules/contests/ContestEscrow.sol";
import {PrizeInfo, PrizeType} from "contracts/modules/contests/shared/PrizeInfo.sol";
import {MockRegistry} from "contracts/mocks/MockRegistry.sol";
import {TestToken} from "contracts/mocks/TestToken.sol";

contract ContestEscrowStressTest is Test {
    ContestEscrow internal escrow;
    TestToken internal token;
    address internal creator = address(0xCAFE);

    function setUp() public {
        token = new TestToken("T", "T");
        uint256 count = 25;
        PrizeInfo[] memory prizes = new PrizeInfo[](count);
        for (uint256 i; i < count; ++i) {
            prizes[i] = PrizeInfo({
                prizeType: PrizeType.MONETARY,
                token: address(token),
                amount: 1 ether,
                distribution: 0,
                uri: ""
            });
        }
        MockRegistry reg = new MockRegistry();
        escrow = new ContestEscrow(creator, prizes, address(reg), 0, address(token), block.timestamp + 1 days);
        token.transfer(address(escrow), count * 1 ether);
    }

    function testFinalizeInBatches() public {
        uint256 count = 25;
        address[] memory winners = new address[](count);
        for (uint256 i; i < count; ++i) {
            winners[i] = address(uint160(i + 100));
        }

        vm.prank(creator);
        escrow.finalize(winners, 0);
        assertEq(escrow.processedWinners(), 20);
        assertFalse(escrow.finalized());

        vm.prank(creator);
        escrow.finalize(winners, 0);
        assertEq(escrow.processedWinners(), count);
        assertTrue(escrow.finalized());
        assertEq(token.balanceOf(winners[0]), 1 ether);
        assertEq(token.balanceOf(winners[count - 1]), 1 ether);
    }
}

