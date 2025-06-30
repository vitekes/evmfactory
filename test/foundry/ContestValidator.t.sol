// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {AccessControlCenter} from "contracts/core/AccessControlCenter.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ContestValidator} from "contracts/modules/contests/ContestValidator.sol";
import {MockValidator} from "contracts/mocks/MockValidator.sol";
import {TestToken} from "contracts/mocks/TestToken.sol";
import {PrizeInfo, PrizeType} from "contracts/modules/contests/shared/PrizeInfo.sol";
import {ZeroAddress, NotAllowedToken} from "contracts/errors/Errors.sol";

contract ContestValidatorTest is Test {
    AccessControlCenter internal acc;
    ContestValidator internal val;
    MockValidator internal mval;
    TestToken internal token;
    address internal governor = address(this);
    address internal other = address(0xBEEF);

    function setUp() public {
        AccessControlCenter accImpl = new AccessControlCenter();
        bytes memory accData = abi.encodeCall(AccessControlCenter.initialize, governor);
        ERC1967Proxy accProxy = new ERC1967Proxy(address(accImpl), accData);
        acc = AccessControlCenter(address(accProxy));
        acc.grantRole(acc.GOVERNOR_ROLE(), governor);
        mval = new MockValidator();
        val = new ContestValidator(address(acc), address(mval));
        token = new TestToken("T", "T");
    }

    function testValidatePrizeAllowed() public {
        mval.setToken(address(token), true);
        PrizeInfo memory prize =
            PrizeInfo({prizeType: PrizeType.MONETARY, token: address(token), amount: 1 ether, distribution: 0, uri: ""});
        val.validatePrize(prize);
    }

    function testValidatePrizeInvalidToken() public {
        mval.setToken(address(token), false);
        PrizeInfo memory prize =
            PrizeInfo({prizeType: PrizeType.MONETARY, token: address(token), amount: 1 ether, distribution: 0, uri: ""});
        vm.expectRevert(NotAllowedToken.selector);
        val.validatePrize(prize);
    }

    function testSetTokenValidator() public {
        MockValidator newVal = new MockValidator();
        vm.prank(governor);
        val.setTokenValidator(address(newVal));
        assertEq(address(val.tokenValidator()), address(newVal));
    }

    function testSetTokenValidatorZeroReverts() public {
        vm.prank(governor);
        vm.expectRevert(ZeroAddress.selector);
        val.setTokenValidator(address(0));
    }
}
