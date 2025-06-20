// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {EventRouter} from "contracts/core/EventRouter.sol";
import {AccessControlCenter} from "contracts/core/AccessControlCenter.sol";

contract EventRouterTest is Test {
    AccessControlCenter acc;
    EventRouter router;

    function setUp() public {
        acc = new AccessControlCenter();
        acc.initialize(address(this));
        router = new EventRouter();
        router.initialize(address(acc));
        acc.grantRole(acc.MODULE_ROLE(), address(this));
    }

    function testRouteUnknownKind() public {
        vm.expectRevert("InvalidKind()");
        router.route(EventRouter.EventKind.Unknown, "");
    }
}
