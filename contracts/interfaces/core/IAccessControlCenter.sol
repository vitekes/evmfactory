// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IAccessControlCenter {
    function grantMultipleRoles(address account, bytes32[] calldata roles) external;
    function hasAnyRole(address account, bytes32[] memory roles) external view returns (bool);
}
