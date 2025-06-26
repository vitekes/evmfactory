// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {ContestEscrow} from "contracts/modules/contests/ContestEscrow.sol";
import {PrizeInfo, PrizeType} from "contracts/modules/contests/shared/PrizeInfo.sol";
import {MockRegistry} from "contracts/mocks/MockRegistry.sol";
import {TestToken} from "contracts/mocks/TestToken.sol";

contract ContestEscrowTest is Test {
    ContestEscrow internal escrow;
    TestToken internal token;
    address internal creator = address(0xCAFE);
    address internal w1 = address(0x1);
    address internal w2 = address(0x2);

    function setUp() public {
        token = new TestToken("T", "T");
        PrizeInfo[] memory prizes = new PrizeInfo[](2);
        prizes[0] = PrizeInfo({prizeType: PrizeType.MONETARY, token: address(token), amount: 100 ether, distribution: 0, uri: ""});
        prizes[1] = PrizeInfo({prizeType: PrizeType.MONETARY, token: address(token), amount: 50 ether, distribution: 0, uri: ""});
        MockRegistry reg = new MockRegistry();
        escrow = new ContestEscrow(creator, prizes, address(reg), 0, address(token), block.timestamp + 1 days);
        token.transfer(address(escrow), 150 ether);
    }

    function testFinalizeDistributesPrizes() public {
        address[] memory winners = new address[](2);
        winners[0] = w1;
        winners[1] = w2;
        vm.prank(creator);
        escrow.finalize(winners, 0, 0);
        assertEq(token.balanceOf(w1), 100 ether);
        assertEq(token.balanceOf(w2), 50 ether);
        assertTrue(escrow.finalized());
    }
}

