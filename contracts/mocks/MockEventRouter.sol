// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract MockEventRouter {
    enum EventKind {
        ContestFinalized
    }

    function route(EventKind /* kind */, bytes calldata /* payload */) external {}
}
