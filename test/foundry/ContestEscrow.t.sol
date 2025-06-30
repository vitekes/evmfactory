// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {ContestEscrow} from "contracts/modules/contests/ContestEscrow.sol";
import {PrizeInfo, PrizeType} from "contracts/modules/contests/shared/PrizeInfo.sol";
import {MockRegistry} from "contracts/mocks/MockRegistry.sol";
import {TestToken} from "contracts/mocks/TestToken.sol";
import {GracePeriodNotExpired} from "contracts/errors/Errors.sol";

contract ContestEscrowTest is Test {
    ContestEscrow internal escrow;
    TestToken internal token;
    address internal creator = address(0xCAFE);
    address internal w1 = address(0x1);
    address internal w2 = address(0x2);

    function setUp() public {
        token = new TestToken("T", "T");
        PrizeInfo[] memory prizes = new PrizeInfo[](2);
        prizes[0] = PrizeInfo({
            prizeType: PrizeType.MONETARY,
            token: address(token),
            amount: 100 ether,
            distribution: 0,
            uri: ""
        });
        prizes[1] = PrizeInfo({
            prizeType: PrizeType.MONETARY,
            token: address(token),
            amount: 50 ether,
            distribution: 0,
            uri: ""
        });
        MockRegistry reg = new MockRegistry();
        escrow = new ContestEscrow(creator, prizes, address(reg), 0, address(token), block.timestamp + 1 days);
        token.transfer(address(escrow), 150 ether);
    }

    function testFinalizeDistributesPrizes() public {
        address[] memory winners = new address[](2);
        winners[0] = w1;
        winners[1] = w2;
        vm.prank(creator);
        escrow.finalize(winners, 0);
        assertEq(token.balanceOf(w1), 100 ether);
        assertEq(token.balanceOf(w2), 50 ether);
        assertTrue(escrow.finalized());
    }

    function testCancelReturnsFunds() public {
        vm.prank(creator);
        escrow.cancel();
        assertEq(token.balanceOf(creator), 150 ether);
        assertTrue(escrow.finalized());
    }

    function testEmergencyWithdrawAfterGrace() public {
        uint256 warpTo = escrow.deadline() + escrow.GRACE_PERIOD() + 1;
        vm.warp(warpTo);
        vm.prank(creator);
        escrow.emergencyWithdraw();
        assertEq(token.balanceOf(creator), 150 ether);
        assertTrue(escrow.finalized());
    }

    function testEmergencyWithdrawBeforeGraceReverts() public {
        vm.warp(block.timestamp + 1 days);
        vm.prank(creator);
        vm.expectRevert(GracePeriodNotExpired.selector);
        escrow.emergencyWithdraw();
    }

    function testFinalizeDescendingDistribution() public {
        PrizeInfo[] memory prizes = new PrizeInfo[](3);
        prizes[0] = PrizeInfo({
            prizeType: PrizeType.MONETARY,
            token: address(token),
            amount: 60 ether,
            distribution: 1,
            uri: ""
        });
        prizes[1] = PrizeInfo({
            prizeType: PrizeType.MONETARY,
            token: address(token),
            amount: 60 ether,
            distribution: 1,
            uri: ""
        });
        prizes[2] = PrizeInfo({
            prizeType: PrizeType.MONETARY,
            token: address(token),
            amount: 60 ether,
            distribution: 1,
            uri: ""
        });
        MockRegistry reg = new MockRegistry();
        ContestEscrow esc =
            new ContestEscrow(creator, prizes, address(reg), 0, address(token), block.timestamp + 1 days);
        token.transfer(address(esc), 180 ether);
        address[] memory winners = new address[](3);
        winners[0] = w1;
        winners[1] = w2;
        winners[2] = address(0x3);
        vm.prank(creator);
        esc.finalize(winners, 0);
        assertEq(token.balanceOf(w1), 30 ether);
        assertEq(token.balanceOf(w2), 20 ether);
    }

    function testFinalizePromoPrize() public {
        PrizeInfo[] memory prizes = new PrizeInfo[](1);
        prizes[0] = PrizeInfo({prizeType: PrizeType.PROMO, token: address(0), amount: 0, distribution: 0, uri: "promo"});
        MockRegistry reg = new MockRegistry();
        ContestEscrow esc = new ContestEscrow(creator, prizes, address(reg), 0, address(token), block.timestamp + 1 days);
        address[] memory winners = new address[](1);
        winners[0] = w1;
        vm.prank(creator);
        esc.finalize(winners, 0);
        assertTrue(esc.finalized());
    }

    function testFinalizeMixedPrizes() public {
        PrizeInfo[] memory prizes = new PrizeInfo[](2);
        prizes[0] = PrizeInfo({prizeType: PrizeType.MONETARY, token: address(token), amount: 1 ether, distribution: 0, uri: ""});
        prizes[1] = PrizeInfo({prizeType: PrizeType.PROMO, token: address(0), amount: 0, distribution: 0, uri: "promo"});
        MockRegistry reg = new MockRegistry();
        ContestEscrow esc = new ContestEscrow(creator, prizes, address(reg), 0, address(token), block.timestamp + 1 days);
        token.transfer(address(esc), 1 ether);
        address[] memory winners = new address[](2);
        winners[0] = w1;
        winners[1] = w2;
        vm.prank(creator);
        esc.finalize(winners, 0);
        assertEq(token.balanceOf(w1), 1 ether);
        assertTrue(esc.finalized());
    }
}
