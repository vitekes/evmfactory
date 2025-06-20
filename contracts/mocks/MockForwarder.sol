// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../core/AccessControlCenter.sol";

contract MockForwarder {
    AccessControlCenter public access;

    error InvalidForwarder();

    constructor(address _access) {
        access = AccessControlCenter(_access);
    }

    function execute(address target, bytes calldata data) external {
        if (!access.hasRole(access.RELAYER_ROLE(), msg.sender)) revert InvalidForwarder();
        (bool ok, bytes memory err) = target.call(data);
        if (!ok) {
            assembly {
                revert(add(err, 32), mload(err))
            }
        }
    }
}
