// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {MockAccessControlCenter} from "contracts/mocks/MockAccessControlCenter.sol";
import {Registry} from "contracts/core/Registry.sol";
import {ContestEscrow} from "contracts/modules/contests/ContestEscrow.sol";
import {PrizeInfo, PrizeType} from "contracts/modules/contests/shared/PrizeInfo.sol";
import {TestToken} from "contracts/mocks/TestToken.sol";

contract MockRouter {
    event Routed(uint8 kind, bytes payload);

    function route(uint8 kind, bytes calldata payload) external {
        emit Routed(kind, payload);
    }
}

contract MockNFTManager {
    event MintBatch(address[] recipients, string[] uris, bool soulbound);

    function mintBatch(address[] calldata recipients, string[] calldata uris, bool soulbound) external {
        emit MintBatch(recipients, uris, soulbound);
    }
}

contract ContestFlowTest is Test {
    Registry registry;
    MockAccessControlCenter acc;
    TestToken token;
    MockRouter router;
    MockNFTManager nft;

    bytes32 constant MODULE_ID = keccak256("Contest");

    function setUp() public {
        acc = new MockAccessControlCenter();
        registry = new Registry();
        registry.initialize(address(acc));
        registry.registerFeature(MODULE_ID, address(1), 0);

        router = new MockRouter();
        nft = new MockNFTManager();
        registry.setModuleServiceAlias(MODULE_ID, "EventRouter", address(router));
        registry.setModuleServiceAlias(MODULE_ID, "NFTManager", address(nft));

        token = new TestToken("T", "T");
    }

    function _deployEscrow() internal returns (ContestEscrow esc) {
        PrizeInfo[] memory prizes = new PrizeInfo[](3);
        prizes[0] = PrizeInfo({
            prizeType: PrizeType.MONETARY,
            token: address(token),
            amount: 10 ether,
            distribution: 0,
            uri: ""
        });
        prizes[1] =
            PrizeInfo({prizeType: PrizeType.MONETARY, token: address(token), amount: 5 ether, distribution: 0, uri: ""});
        prizes[2] =
            PrizeInfo({prizeType: PrizeType.PROMO, token: address(0), amount: 0, distribution: 0, uri: "ipfs://promo"});

        esc = new ContestEscrow(registry, address(this), prizes, address(token), 0, 0, new address[](0), "");
        token.transfer(address(esc), 15 ether);
    }

    function testFinalizeMultiPrize() public {
        ContestEscrow esc = _deployEscrow();
        address[] memory winners = new address[](3);
        winners[0] = address(1);
        winners[1] = address(2);
        winners[2] = address(3);

        vm.expectEmit(true, true, true, true);
        emit ContestEscrow.MonetaryPrizePaid(winners[0], 10 ether);
        vm.expectEmit(true, true, true, true);
        emit ContestEscrow.MonetaryPrizePaid(winners[1], 5 ether);
        vm.expectEmit(true, true, true, true);
        emit ContestEscrow.PromoPrizeIssued(2, winners[2], "ipfs://promo");

        esc.finalize(winners);

        assertEq(token.balanceOf(winners[0]), 10 ether);
        assertEq(token.balanceOf(winners[1]), 5 ether);
        assertTrue(esc.isFinalized());
        assertEq(esc.winners(0), winners[0]);
        assertEq(esc.winners(1), winners[1]);
        assertEq(esc.winners(2), winners[2]);
    }

    function testFinalizeWrongWinnersCount() public {
        ContestEscrow esc = _deployEscrow();
        address[] memory winners = new address[](2);
        winners[0] = address(1);
        winners[1] = address(2);
        vm.expectRevert("WrongWinnersCount()");
        esc.finalize(winners);
    }
}
