// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './AccessControlCenter.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '../errors/Errors.sol';

contract Registry is Initializable, UUPSUpgradeable {
    /// @dev Хранение информации о фичах
    struct Feature {
        address implementation;
        uint8 context; // Напр., 0 - конкурсы, 1 - маркетплейс и т.д.
        bool exists;
    }

    /// @notice Адрес контракта AccessControlCenter
    AccessControlCenter public access;

    /// @notice Все зарегистрированные фичи
    mapping(bytes32 => Feature) private features;

    /// @notice Ядровые сервисы (по id, например "Validator", "FeeManager")
    mapping(bytes32 => address) private coreServices;
    /// @notice Сервисы, привязанные к конкретным модулям (moduleId => serviceId => address)
    mapping(bytes32 => mapping(bytes32 => address)) private moduleServices;

    /// Events
    event FeatureRegistered(bytes32 indexed id, address implementation, uint8 context);
    event CoreServiceSet(bytes32 indexed id, address serviceAddress);
    event ModuleServiceSet(bytes32 indexed moduleId, bytes32 indexed serviceId, address serviceAddress);
    event ModuleRegistered(bytes32 indexed moduleId, string serviceAlias, address serviceAddress);

    modifier onlyAdmin() {
        if (!access.hasRole(access.DEFAULT_ADMIN_ROLE(), msg.sender)) revert NotAdmin();
        _;
    }

    modifier onlyFeatureOwner() {
        if (!access.hasRole(access.FEATURE_OWNER_ROLE(), msg.sender)) revert NotFeatureOwner();
        _;
    }

    function initialize(address accessControl) public initializer {
        __UUPSUpgradeable_init();
        access = AccessControlCenter(accessControl);
    }

    function registerFeature(bytes32 id, address impl, uint8 context) external onlyFeatureOwner {
        if (impl == address(0)) revert InvalidImplementation();
        features[id] = Feature(impl, context, true);
        emit FeatureRegistered(id, impl, context);
    }

    function getFeature(bytes32 id) external view returns (address impl, uint8 context) {
        Feature storage f = features[id];
        if (!f.exists) revert NotFound();
        return (f.implementation, f.context);
    }

    function getContext(bytes32 id) external view returns (uint8) {
        Feature storage f = features[id];
        if (!f.exists) revert NotFound();
        return f.context;
    }

    function setCoreService(bytes32 serviceId, address addr) external onlyAdmin {
        coreServices[serviceId] = addr;
        emit CoreServiceSet(serviceId, addr);
    }

    function getCoreService(bytes32 serviceId) external view returns (address) {
        return coreServices[serviceId];
    }

    /// @notice Привязать сервис к конкретному модулю
    function setModuleService(bytes32 moduleId, bytes32 serviceId, address addr) public onlyFeatureOwner {
        if (!features[moduleId].exists) revert ModuleNotRegistered();
        moduleServices[moduleId][serviceId] = addr;
        emit ModuleServiceSet(moduleId, serviceId, addr);
    }

    function setModuleServiceAlias(
        bytes32 moduleId,
        string calldata serviceAlias,
        address addr
    ) external onlyFeatureOwner {
        bytes32 serviceId = keccak256(bytes(serviceAlias));
        setModuleService(moduleId, serviceId, addr);
        emit ModuleRegistered(moduleId, serviceAlias, addr);
    }

    /// @notice Получить сервис, закреплённый за модулем
    function getModuleService(bytes32 moduleId, bytes32 serviceId) external view returns (address) {
        return moduleServices[moduleId][serviceId];
    }

    function getModuleService(bytes32 moduleId, string calldata serviceAlias) external view returns (address) {
        return moduleServices[moduleId][keccak256(bytes(serviceAlias))];
    }

    /// Позволяет заменить AccessControlCenter, если понадобится
    function setAccessControl(address newAccess) external onlyAdmin {
        access = AccessControlCenter(newAccess);
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyAdmin {
        if (newImplementation == address(0)) revert InvalidImplementation();
    }

    uint256[50] private __gap;
}
