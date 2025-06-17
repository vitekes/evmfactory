// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./AccessControlCenter.sol";

contract EventRouter {
    AccessControlCenter public access;
    event Routed(bytes32 indexed eventType, bytes data);

    constructor(address accessControl) {
        access = AccessControlCenter(accessControl);
    }

    function route(bytes32 eventType, bytes calldata data) external {
        require(access.hasRole(access.MODULE_ROLE(), msg.sender), "not module");
        emit Routed(eventType, data);
    }
}
