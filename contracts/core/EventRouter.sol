// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract EventRouter {
    event Routed(bytes32 indexed eventType, bytes data);

    constructor() {}

    function route(bytes32 eventType, bytes calldata data) external {
        emit Routed(eventType, data);
    }
}
