// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {ContestFactory} from "contracts/modules/contests/ContestFactory.sol";
import {ContestEscrow} from "contracts/modules/contests/ContestEscrow.sol";
import {PrizeInfo, PrizeType} from "contracts/modules/contests/shared/PrizeInfo.sol";
import {MockRegistry} from "contracts/mocks/MockRegistry.sol";
import {MockFeeManager} from "contracts/mocks/MockFeeManager.sol";
import {AccessControlCenter} from "contracts/core/AccessControlCenter.sol";
import {TestToken} from "contracts/mocks/TestToken.sol";
import {InvalidPrizeData, NotGovernor} from "contracts/errors/Errors.sol";
import {CoreDefs} from "contracts/interfaces/CoreDefs.sol";
import {IContestValidator} from "contracts/modules/contests/interfaces/IContestValidator.sol";

contract DummyValidator is IContestValidator {
    function validatePrize(PrizeInfo calldata) external pure {}
    function isTokenAllowed(address) external pure returns (bool) { return true; }
    function isDistributionValid(uint256, uint8) external pure returns (bool) { return true; }
}

contract ContestFactoryTest is Test {
    ContestFactory internal factory;
    MockRegistry internal registry;
    AccessControlCenter internal acc;
    MockFeeManager internal fee;
    TestToken internal token;
    DummyValidator internal validator;

    bytes32 internal constant MODULE_ID = CoreDefs.CONTEST_MODULE_ID;

    function setUp() public {
        token = new TestToken("T", "T");
        registry = new MockRegistry();
        fee = new MockFeeManager();
        acc = new AccessControlCenter();
        acc.initialize(address(this));
        acc.grantRole(acc.GOVERNOR_ROLE(), address(this));
        registry.setCoreService(keccak256("AccessControlCenter"), address(acc));
        validator = new DummyValidator();
        registry.setModuleServiceAlias(MODULE_ID, "Validator", address(validator));
        factory = new ContestFactory(address(registry), address(fee));
    }

    function _prizes() internal view returns (PrizeInfo[] memory prizes) {
        prizes = new PrizeInfo[](1);
        prizes[0] = PrizeInfo({
            prizeType: PrizeType.MONETARY,
            token: address(token),
            amount: 100 ether,
            distribution: 0,
            uri: ""
        });
    }

    function testCreateContestTransfersFunds() public {
        PrizeInfo[] memory prizes = _prizes();
        token.approve(address(factory), 100 ether);
        address esc = factory.createContest(prizes, "");
        assertEq(token.balanceOf(esc), 100 ether);
        assertEq(ContestEscrow(esc).creator(), address(this));
    }

    function testOnlyGovernor() public {
        PrizeInfo[] memory prizes = _prizes();
        address other = address(0x1);
        vm.prank(other);
        vm.expectRevert(NotGovernor.selector);
        factory.createContest(prizes, "");
    }

    function testInvalidPrizeReverts() public {
        PrizeInfo[] memory prizes = new PrizeInfo[](1);
        prizes[0] = PrizeInfo({
            prizeType: PrizeType.MONETARY,
            token: address(token),
            amount: 0,
            distribution: 0,
            uri: ""
        });
        vm.expectRevert(InvalidPrizeData.selector);
        factory.createContest(prizes, "");
    }
}
