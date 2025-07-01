// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract MockValidator {
    mapping(address => bool) public allowed;

    function setToken(address token, bool status) external {
        allowed[token] = status;
    }

    function isAllowed(address token) external view returns (bool) {
        return allowed[token];
    }
}
