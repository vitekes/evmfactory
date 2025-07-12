// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../interfaces/IProcessorRegistry.sol";
import "../interfaces/IPaymentProcessor.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title ProcessorRegistry
/// @notice Реестр процессоров для управления регистрацией и порядком
contract ProcessorRegistry is IProcessorRegistry, AccessControl {
    bytes32 public constant REGISTRY_ADMIN_ROLE = keccak256("REGISTRY_ADMIN_ROLE");

    mapping(string => address) private processorsByName;
    mapping(bytes32 => address[]) private moduleProcessors;
    mapping(bytes32 => mapping(string => bool)) private moduleProcessorEnabled;

    event ProcessorRegistered(address indexed processor, string name, uint256 position);
    event ProcessorRemoved(string indexed name, address indexed processor);
    event ProcessorOrderUpdated(bytes32 indexed moduleId, string[] newOrder);
    event ProcessorStatusChanged(bytes32 indexed moduleId, string indexed name, bool enabled);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(REGISTRY_ADMIN_ROLE, msg.sender);
    }

    function registerProcessor(address processor, uint256 position) external override onlyRole(REGISTRY_ADMIN_ROLE) returns (bool success) {
        require(processor != address(0), "ProcessorRegistry: zero address");

        string memory name = IPaymentProcessor(processor).getName();
        require(bytes(name).length > 0, "ProcessorRegistry: empty name");
        require(processorsByName[name] == address(0), "ProcessorRegistry: already registered");

        processorsByName[name] = processor;

        emit ProcessorRegistered(processor, name, position);
        return true;
    }

    function removeProcessor(string calldata processorName) external override onlyRole(REGISTRY_ADMIN_ROLE) returns (bool success) {
        address processor = processorsByName[processorName];
        require(processor != address(0), "ProcessorRegistry: not found");

        delete processorsByName[processorName];

        emit ProcessorRemoved(processorName, processor);
        return true;
    }

    function getProcessorByName(string calldata name) external view override returns (address processorAddress) {
        return processorsByName[name];
    }

    function getProcessorChain(bytes32 moduleId) external view override returns (address[] memory processors) {
        return moduleProcessors[moduleId];
    }

    function updateProcessorOrder(bytes32 moduleId, string[] calldata newOrder) external override onlyRole(REGISTRY_ADMIN_ROLE) returns (bool success) {
        address[] memory newProcessors = new address[](newOrder.length);

        for (uint256 i = 0; i < newOrder.length; i++) {
            address processor = processorsByName[newOrder[i]];
            require(processor != address(0), "ProcessorRegistry: processor not found");
            newProcessors[i] = processor;
        }

        moduleProcessors[moduleId] = newProcessors;

        emit ProcessorOrderUpdated(moduleId, newOrder);
        return true;
    }

    function setProcessorEnabled(bytes32 moduleId, string calldata processorName, bool enabled) external override onlyRole(REGISTRY_ADMIN_ROLE) returns (bool success) {
        require(processorsByName[processorName] != address(0), "ProcessorRegistry: processor not found");

        moduleProcessorEnabled[moduleId][processorName] = enabled;

        emit ProcessorStatusChanged(moduleId, processorName, enabled);
        return true;
    }

    function isProcessorEnabled(bytes32 moduleId, string calldata processorName) external view override returns (bool enabled) {
        return moduleProcessorEnabled[moduleId][processorName];
    }
}
