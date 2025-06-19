// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccessControlCenter.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../errors/Errors.sol";

contract EventRouter is Initializable, UUPSUpgradeable {
    AccessControlCenter public access;
    event Routed(bytes32 indexed eventType, bytes data);

    function initialize(address accessControl) public initializer {
        __UUPSUpgradeable_init();
        access = AccessControlCenter(accessControl);
    }

    function route(bytes32 eventType, bytes calldata data) external {
        if (!access.hasRole(access.MODULE_ROLE(), msg.sender)) revert NotModule();
        emit Routed(eventType, data);
    }

    function _authorizeUpgrade(address newImplementation) internal view override {
        if (!access.hasRole(access.DEFAULT_ADMIN_ROLE(), msg.sender)) revert NotAdmin();
        if (newImplementation == address(0)) revert InvalidImplementation();
    }

    uint256[50] private __gap;
}
