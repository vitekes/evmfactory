// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

contract EventRouter {
    event Routed(bytes32 indexed eventType, bytes data);

    constructor() {}

    function route(bytes32 eventType, bytes calldata data) external {
        emit Routed(eventType, data);
    }
}
