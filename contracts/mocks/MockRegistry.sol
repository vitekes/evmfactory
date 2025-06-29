// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract MockRegistry {
    mapping(bytes32 => mapping(bytes32 => address)) public moduleServices;
    mapping(bytes32 => address) public coreServices;

    mapping(bytes32 => address) public features;

    function setModuleServiceAlias(bytes32 moduleId, string calldata serviceAlias, address addr) external {
        moduleServices[moduleId][keccak256(bytes(serviceAlias))] = addr;
    }

    function getModuleServiceByAlias(bytes32 moduleId, string calldata serviceAlias) external view returns (address) {
        return moduleServices[moduleId][keccak256(bytes(serviceAlias))];
    }

    function getModuleService(bytes32 moduleId, bytes32 serviceId) external view returns (address) {
        return moduleServices[moduleId][serviceId];
    }

    function setCoreService(bytes32 serviceId, address addr) external {
        coreServices[serviceId] = addr;
    }

    function getCoreService(bytes32 serviceId) external view returns (address) {
        return coreServices[serviceId];
    }

    function registerFeature(bytes32 id, address impl, uint8) external {
        features[id] = impl;
    }
}
