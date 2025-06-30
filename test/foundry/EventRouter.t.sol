// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {AccessControlCenter} from "contracts/core/AccessControlCenter.sol";
import {EventRouter} from "contracts/core/EventRouter.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {InvalidKind} from "contracts/errors/Errors.sol";

contract EventRouterTest is Test {
    AccessControlCenter internal acc;
    EventRouter internal router;
    address internal module = address(0xBEEF);

    function setUp() public {
        AccessControlCenter accImpl = new AccessControlCenter();
        bytes memory accData = abi.encodeCall(AccessControlCenter.initialize, address(this));
        ERC1967Proxy accProxy = new ERC1967Proxy(address(accImpl), accData);
        acc = AccessControlCenter(address(accProxy));
        acc.grantRole(acc.MODULE_ROLE(), module);

        EventRouter routerImpl = new EventRouter();
        bytes memory routerData = abi.encodeCall(EventRouter.initialize, address(acc));
        ERC1967Proxy routerProxy = new ERC1967Proxy(address(routerImpl), routerData);
        router = EventRouter(address(routerProxy));
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
