// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '../interfaces/IEventRouter.sol';
import '../interfaces/IEventPayload.sol';
import '../interfaces/IRegistry.sol';
import '../interfaces/IAccessControlCenter.sol';
import '../interfaces/CoreDefs.sol';
import '../errors/Errors.sol';

/// @title CoreKernel
/// @notice Unified contract for roles and service registry
contract CoreKernel is Initializable, AccessControlUpgradeable, UUPSUpgradeable, IAccessControlCenter, IRegistry {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // Roles
    bytes32 public constant FEATURE_OWNER_ROLE = keccak256('FEATURE_OWNER_ROLE');
    bytes32 public constant OPERATOR_ROLE = keccak256('OPERATOR_ROLE');
    bytes32 public constant RELAYER_ROLE = keccak256('RELAYER_ROLE');
    bytes32 public constant MODULE_ROLE = keccak256('MODULE_ROLE');
    bytes32 public constant AUTOMATION_ROLE = keccak256('AUTOMATION_ROLE');
    bytes32 public constant GOVERNOR_ROLE = keccak256('GOVERNOR_ROLE');

    address public adminAddr;

    struct Feature {
        address implementation;
        uint8 context;
        bool exists;
    }

    mapping(bytes32 => Feature) private features;
    mapping(bytes32 => address) private coreServices;
    mapping(bytes32 => mapping(bytes32 => address)) private moduleServices;

    event ModuleRegistered(bytes32 indexed moduleId, string serviceAlias, address serviceAddress);

    function initialize(address admin) public initializer {
        if (admin == address(0)) revert InvalidAddress();
        __AccessControl_init();
        __UUPSUpgradeable_init();
        adminAddr = admin;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // AccessControlCenter functions
    function grantMultipleRoles(address account, bytes32[] calldata roles) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < roles.length; i++) {
            _grantRole(roles[i], account);
            _emitRoleGrantedEvent(roles[i], account, msg.sender);
        }
    }

    function hasAnyRole(address account, bytes32[] memory roles) public view override returns (bool) {
        for (uint256 i = 0; i < roles.length; i++) {
            if (hasRole(roles[i], account)) {
                return true;
            }
        }
        return false;
    }

    // Registry functions
    function registerFeature(bytes32 id, address impl, uint8 context) external override onlyRole(FEATURE_OWNER_ROLE) {
        if (impl == address(0)) revert InvalidImplementation();
        features[id] = Feature(impl, context, true);
        _emitFeatureEvent(id, address(0), impl, context);
    }

    function upgradeFeature(bytes32 id, address newImpl) external override onlyRole(FEATURE_OWNER_ROLE) {
        if (newImpl == address(0)) revert InvalidAddress();
        Feature storage f = features[id];
        if (!f.exists) revert NotFound();
        address oldImpl = f.implementation;
        f.implementation = newImpl;
        _emitFeatureEvent(id, oldImpl, newImpl, f.context);
    }

    function getFeature(bytes32 id) external view override returns (address impl, uint8 context) {
        Feature storage f = features[id];
        if (!f.exists) revert NotFound();
        return (f.implementation, f.context);
    }

    function getContext(bytes32 id) external view override returns (uint8) {
        Feature storage f = features[id];
        if (!f.exists) revert NotFound();
        return f.context;
    }

    function setCoreService(bytes32 serviceId, address addr) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        coreServices[serviceId] = addr;
        _emitServiceEvent(serviceId, addr, bytes32(0));
    }

    function getCoreService(bytes32 serviceId) external view override returns (address) {
        return coreServices[serviceId];
    }

    function setModuleService(bytes32 moduleId, bytes32 serviceId, address addr) public override onlyRole(FEATURE_OWNER_ROLE) {
        if (!features[moduleId].exists) revert ModuleNotRegistered();
        moduleServices[moduleId][serviceId] = addr;
        _emitServiceEvent(serviceId, addr, moduleId);
    }

    function setModuleServiceAlias(bytes32 moduleId, string calldata serviceAlias, address addr) external override onlyRole(FEATURE_OWNER_ROLE) {
        bytes32 serviceId = keccak256(bytes(serviceAlias));
        setModuleService(moduleId, serviceId, addr);
        emit ModuleRegistered(moduleId, serviceAlias, addr);
    }

    function getModuleService(bytes32 moduleId, bytes32 serviceId) external view override returns (address) {
        return moduleServices[moduleId][serviceId];
    }

    function getModuleServiceByAlias(bytes32 moduleId, string calldata serviceAlias) external view override returns (address) {
        return moduleServices[moduleId][keccak256(bytes(serviceAlias))];
    }

    function setAccessControl(address /*newAccess*/) external pure override {
        revert('deprecated');
    }

    // Internal helpers
    function _getEventRouter() internal view returns (address router) {
        router = coreServices[CoreDefs.SERVICE_EVENT_ROUTER];
    }

    function _emitRoleGrantedEvent(bytes32 role, address account, address sender) internal {
        address router = _getEventRouter();
        if (router != address(0)) {
            IEventPayload.ServiceEvent memory eventData = IEventPayload.ServiceEvent({
                serviceId: role,
                serviceAddress: account,
                moduleId: bytes32(uint256(uint160(sender))),
                version: 1
            });
            IEventRouter(router).route(IEventRouter.EventKind.UserRegistered, abi.encode(eventData));
        }
    }

    function _emitFeatureEvent(bytes32 id, address oldImpl, address newImpl, uint8 context) internal {
        address router = _getEventRouter();
        if (router != address(0)) {
            IEventPayload.FeatureEvent memory eventData = IEventPayload.FeatureEvent({
                featureId: id,
                oldImplementation: oldImpl,
                newImplementation: newImpl,
                context: context,
                version: 1
            });
            IEventRouter(router).route(IEventRouter.EventKind.FeatureUpgraded, abi.encode(eventData));
        }
    }

    function _emitServiceEvent(bytes32 serviceId, address addr, bytes32 moduleId) internal {
        address router = _getEventRouter();
        if (router != address(0)) {
            IEventPayload.ServiceEvent memory eventData = IEventPayload.ServiceEvent({
                serviceId: serviceId,
                serviceAddress: addr,
                moduleId: moduleId,
                version: 1
            });
            IEventRouter(router).route(IEventRouter.EventKind.ServiceRegistered, abi.encode(eventData));
        }
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newImplementation == address(0)) revert InvalidImplementation();
    }

    uint256[48] private __gap;
}
