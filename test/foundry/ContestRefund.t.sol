// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {AccessControlCenter} from "contracts/core/AccessControlCenter.sol";
import {Registry} from "contracts/core/Registry.sol";
import {ContestEscrow} from "contracts/modules/contests/ContestEscrow.sol";
import {PrizeInfo, PrizeType} from "contracts/modules/contests/shared/PrizeInfo.sol";
import {ContestEscrowDeployer} from "./ContestEscrowDeployer.sol";
import {TestToken} from "contracts/mocks/TestToken.sol";

contract MockRouter2 {
    event Routed(uint8 kind, bytes payload);

    function route(uint8 kind, bytes calldata payload) external {
        emit Routed(kind, payload);
    }
}

contract MockNFTManager2 {
    event MintBatch(address[] recipients, string[] uris, bool soulbound);

    function mintBatch(address[] calldata recipients, string[] calldata uris, bool soulbound) external {
        emit MintBatch(recipients, uris, soulbound);
    }
}

contract ContestRefundTest is Test {
    Registry registry;
    AccessControlCenter acc;
    TestToken token;
    MockRouter2 router;
    MockNFTManager2 nft;
    ContestEscrowDeployer deployer;

    bytes32 constant MODULE_ID = keccak256("Contest");

    function setUp() public {
        acc = new AccessControlCenter();
        acc.initialize(address(this));
        acc.grantRole(acc.FEATURE_OWNER_ROLE(), address(this));
        registry = new Registry();
        registry.initialize(address(acc));
        registry.registerFeature(MODULE_ID, address(1), 0);

        router = new MockRouter2();
        nft = new MockNFTManager2();
        registry.setModuleServiceAlias(MODULE_ID, "EventRouter", address(router));
        registry.setModuleServiceAlias(MODULE_ID, "NFTManager", address(nft));

        token = new TestToken("T", "T");
        deployer = new ContestEscrowDeployer();
    }

    function testGasRefund() public {
        PrizeInfo[] memory prizes = new PrizeInfo[](1);
        prizes[0] =
            PrizeInfo({prizeType: PrizeType.MONETARY, token: address(token), amount: 1 ether, distribution: 0, uri: ""});

        ContestEscrow esc = deployer.deploy(registry, address(this), prizes, address(token), 0, 1 ether);
        token.transfer(address(esc), 2 ether);

        address[] memory winners = new address[](1);
        winners[0] = address(1);

        uint256 balBefore = token.balanceOf(address(this));
        vm.txGasPrice(1 gwei);
        vm.expectEmit(true, false, false, false);
        emit ContestEscrow.GasRefunded(address(this), 0);
        // amount checked indirectly via balance increase
        esc.finalize(winners);
        assertGt(token.balanceOf(address(this)), balBefore);
        assertLt(esc.gasPool(), 1 ether);
    }
}
