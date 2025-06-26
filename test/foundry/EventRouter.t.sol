// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {AccessControlCenter} from "contracts/core/AccessControlCenter.sol";
import {EventRouter} from "contracts/core/EventRouter.sol";
import {InvalidKind} from "contracts/errors/Errors.sol";

contract EventRouterTest is Test {
    AccessControlCenter internal acc;
    EventRouter internal router;
    address internal module = address(0xBEEF);

    function setUp() public {
        acc = new AccessControlCenter();
        acc.initialize(address(this));
        acc.grantRole(acc.MODULE_ROLE(), module);

        router = new EventRouter();
        router.initialize(address(acc));
    }

    function testRouteEmitsEvent() public {
        bytes memory data = abi.encode(address(this), uint256(1));
        vm.prank(module);
        vm.expectEmit(true, false, false, true);
        emit EventRouter.EventRouted(EventRouter.EventKind.ListingCreated, data);
        router.route(EventRouter.EventKind.ListingCreated, data);
    }

    function testRouteInvalidKind() public {
        vm.prank(module);
        vm.expectRevert(abi.encodeWithSelector(InvalidKind.selector));
        router.route(EventRouter.EventKind.Unknown, "");
    }
}
