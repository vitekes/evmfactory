// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IAccessControlCenter {
    /// @notice Role management functions
    function hasRole(bytes32 role, address account) external view returns (bool);
    function grantRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function renounceRole(bytes32 role, address account) external;
    function grantMultipleRoles(address account, bytes32[] memory roles) external;

    /// @notice Predefined system roles
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function GOVERNOR_ROLE() external view returns (bytes32);
    function FEATURE_OWNER_ROLE() external view returns (bytes32);
    function MODULE_ROLE() external view returns (bytes32);
    function RELAYER_ROLE() external view returns (bytes32);
    function AUTOMATION_ROLE() external view returns (bytes32);

    /// @notice Check if an account has any of the provided roles
    function hasAnyRole(address account, bytes32[] memory roles) external view returns (bool);
}
