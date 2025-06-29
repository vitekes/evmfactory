// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IRegistry {
    function registerFeature(bytes32 id, address impl, uint8 context) external;

    function upgradeFeature(bytes32 id, address newImpl) external;

    function getFeature(bytes32 id) external view returns (address impl, uint8 context);

    function getContext(bytes32 id) external view returns (uint8);

    function setCoreService(bytes32 serviceId, address addr) external;

    function getCoreService(bytes32 serviceId) external view returns (address);

    function setModuleService(bytes32 moduleId, bytes32 serviceId, address addr) external;

    function getModuleService(bytes32 moduleId, bytes32 serviceId) external view returns (address);

    function setModuleServiceAlias(bytes32 moduleId, string calldata serviceAlias, address addr) external;

    function getModuleServiceByAlias(bytes32 moduleId, string calldata serviceAlias) external view returns (address);
}
