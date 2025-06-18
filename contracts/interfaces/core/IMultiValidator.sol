// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IMultiValidator {
    function initialize(address acl) external;
    function allow(address token, bool allowed) external;
    function bulkAllow(address[] calldata tokens, bool allowed) external;
    function isAllowed(address token) external view returns (bool);
    function setAccessControl(address newAccess) external;
}
