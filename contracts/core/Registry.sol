// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './AccessControlCenter.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '../errors/Errors.sol';
import '../interfaces/CoreDefs.sol';

contract Registry is Initializable, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    /// @dev Storage for feature information
    struct Feature {
        address implementation;
        uint8 context; // e.g. 0 - contests, 1 - marketplace, etc.
        bool exists;
    }

    /// @notice Address of the AccessControlCenter contract
    AccessControlCenter public access;

    /// @notice All registered features
    mapping(bytes32 => Feature) private features;

    /// @notice Core services (by id, e.g. "Validator", "FeeManager")
    mapping(bytes32 => address) private coreServices;
    /// @notice Services bound to specific modules (moduleId => serviceId => address)
    mapping(bytes32 => mapping(bytes32 => address)) private moduleServices;

    /// Events
    event ModuleRegistered(bytes32 indexed moduleId, string serviceAlias, address serviceAddress);
    event ServiceRegistered(bytes32 indexed serviceId, address serviceAddress, bytes32 moduleId);
    event FeatureUpgraded(
        bytes32 indexed featureId,
        address oldImplementation,
        address newImplementation,
        uint8 context
    );

    modifier onlyAdmin() {
        if (!access.hasRole(access.DEFAULT_ADMIN_ROLE(), msg.sender)) revert NotAdmin();
        _;
    }

    modifier onlyFeatureOwner() {
        if (!access.hasRole(access.FEATURE_OWNER_ROLE(), msg.sender)) revert NotFeatureOwner();
        _;
    }

    /// @notice Initialize the registry
    /// @param accessControl Address of AccessControlCenter
    function initialize(address accessControl) public initializer {
        __UUPSUpgradeable_init();
        access = AccessControlCenter(accessControl);
    }

    /// @notice Register a new feature implementation
    /// @param id Feature identifier
    /// @param impl Implementation address
    /// @param context Context value
    function registerFeature(bytes32 id, address impl, uint8 context) external onlyFeatureOwner {
        if (impl == address(0)) revert InvalidImplementation();
        features[id] = Feature(impl, context, true);

        // Отправляем прямое событие
        emit FeatureUpgraded(id, address(0), impl, context);
    }

    function upgradeFeature(bytes32 id, address newImpl) external onlyFeatureOwner {
        if (newImpl == address(0)) revert InvalidAddress();
        Feature storage f = features[id];
        if (!f.exists) revert NotFound();
        address oldImpl = f.implementation;
        f.implementation = newImpl;

        // Отправляем прямое событие
        emit FeatureUpgraded(id, oldImpl, newImpl, f.context);
    }

    /// @notice Get feature implementation and context
    /// @param id Feature identifier
    /// @return impl Implementation address
    /// @return context Feature context
    function getFeature(bytes32 id) external view returns (address impl, uint8 context) {
        Feature storage f = features[id];
        if (!f.exists) revert NotFound();
        return (f.implementation, f.context);
    }

    /// @notice Get context value for a feature
    /// @param id Feature identifier
    /// @return Context value
    function getContext(bytes32 id) external view returns (uint8) {
        Feature storage f = features[id];
        if (!f.exists) revert NotFound();
        return f.context;
    }

    /// @notice Set address for a core service
    /// @param serviceId Service identifier
    /// @param addr Service address
    function setCoreService(bytes32 serviceId, address addr) external onlyAdmin {
        coreServices[serviceId] = addr;

        // Отправляем прямое событие
        emit ServiceRegistered(serviceId, addr, bytes32(0));
    }

    /// @notice Get address of a core service
    /// @param serviceId Service identifier
    /// @return Service address
    function getCoreService(bytes32 serviceId) external view returns (address) {
        return coreServices[serviceId];
    }

    /// @notice Bind a service address to a module
    /// @param moduleId Module identifier
    /// @param serviceId Service identifier
    /// @param addr Service address
    function setModuleService(bytes32 moduleId, bytes32 serviceId, address addr) public onlyFeatureOwner {
        if (!features[moduleId].exists) revert ModuleNotRegistered();
        moduleServices[moduleId][serviceId] = addr;

        // Отправляем прямое событие
        emit ServiceRegistered(serviceId, addr, moduleId);
    }

    /// @notice Bind a service using an alias string
    /// @param moduleId Module identifier
    /// @param serviceAlias Service alias
    /// @param addr Service address
    function setModuleServiceAlias(
        bytes32 moduleId,
        string calldata serviceAlias,
        address addr
    ) external onlyFeatureOwner {
        bytes32 serviceId = keccak256(bytes(serviceAlias));
        setModuleService(moduleId, serviceId, addr);
        emit ModuleRegistered(moduleId, serviceAlias, addr);
    }

    /// @notice Get service assigned to a module
    /// @param moduleId Module identifier
    /// @param serviceId Service identifier
    /// @return Service address
    function getModuleService(bytes32 moduleId, bytes32 serviceId) external view returns (address) {
        return moduleServices[moduleId][serviceId];
    }

    /// @notice Get service assigned to a module by alias
    /// @param moduleId Module identifier
    /// @param serviceAlias Alias used during registration
    /// @return Service address
    function getModuleServiceByAlias(bytes32 moduleId, string calldata serviceAlias) external view returns (address) {
        return moduleServices[moduleId][keccak256(bytes(serviceAlias))];
    }

    /// @notice Replace the AccessControlCenter if needed
    /// @param newAccess New AccessControlCenter address
    function setAccessControl(address newAccess) external onlyAdmin {
        if (newAccess == address(0)) revert InvalidAddress();
        access = AccessControlCenter(newAccess);
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyAdmin {
        if (newImplementation == address(0)) revert InvalidImplementation();
    }

    uint256[50] private __gap;
}
