// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../errors/Errors.sol';
import './CoreDefs.sol';

/**
 * @title CoreSystem
 * @notice Система управления доступом и регистрации компонентов
 */
contract CoreSystem {
    // Роли системы
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant FEATURE_OWNER_ROLE = keccak256('FEATURE_OWNER_ROLE');
    bytes32 public constant OPERATOR_ROLE = keccak256('OPERATOR_ROLE');
    bytes32 public constant AUTOMATION_ROLE = keccak256('AUTOMATION_ROLE');
    bytes32 public constant GOVERNOR_ROLE = keccak256('GOVERNOR_ROLE');

    // Структуры для хранения компонентов
    struct Feature {
        address implementation;
        uint8 context;
        bool exists;
    }

    // Хранение ролей
    mapping(bytes32 => mapping(address => bool)) private roles;
    mapping(bytes32 => address[]) private roleMembers;

    // Хранение компонентов
    mapping(bytes32 => Feature) private features;
    mapping(bytes32 => address) private coreServices;
    mapping(bytes32 => mapping(bytes32 => address)) private moduleServices;

    // События
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event ServiceRegistered(bytes32 indexed serviceId, address serviceAddress, bytes32 moduleId);
    event ModuleRegistered(bytes32 indexed moduleId, string serviceAlias, address serviceAddress);
    event FeatureRegistered(bytes32 indexed featureId, address implementation, uint8 context);
    event FeatureUpgraded(
        bytes32 indexed featureId,
        address oldImplementation,
        address newImplementation,
        uint8 context
    );

    constructor(address admin) {
        if (admin == address(0)) revert InvalidAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // === Управление ролями ===

    modifier onlyRole(bytes32 role) {
        if (!hasRole(role, msg.sender)) revert Forbidden();
        _;
    }

    modifier onlyAdmin() {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert NotAdmin();
        _;
    }

    modifier onlyFeatureOwner() {
        if (!hasRole(FEATURE_OWNER_ROLE, msg.sender)) revert NotFeatureOwner();
        _;
    }

    modifier onlyOperator() {
        if (!hasRole(OPERATOR_ROLE, msg.sender)) revert NotOperator();
        _;
    }

    function hasRole(bytes32 role, address account) public view returns (bool) {
        return roles[role][account];
    }

    function grantRole(bytes32 role, address account) external onlyAdmin {
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external onlyAdmin {
        _revokeRole(role, account);
    }

    function _grantRole(bytes32 role, address account) private {
        if (!roles[role][account]) {
            roles[role][account] = true;
            roleMembers[role].push(account);
            emit RoleGranted(role, account, msg.sender);
        }
    }

    function _revokeRole(bytes32 role, address account) private {
        if (roles[role][account]) {
            roles[role][account] = false;

            // Удаляем аккаунт из списка участников роли
            address[] storage members = roleMembers[role];
            for (uint256 i = 0; i < members.length; i++) {
                if (members[i] == account) {
                    // Заменяем удаляемый элемент последним и уменьшаем массив
                    members[i] = members[members.length - 1];
                    members.pop();
                    break;
                }
            }

            emit RoleRevoked(role, account, msg.sender);
        }
    }

    // === Управление компонентами ===

    function registerFeature(bytes32 id, address impl, uint8 context) external onlyFeatureOwner {
        if (impl == address(0)) revert InvalidImplementation();
        features[id] = Feature(impl, context, true);
        emit FeatureRegistered(id, impl, context);
    }

    function upgradeFeature(bytes32 id, address newImpl) external onlyFeatureOwner {
        if (newImpl == address(0)) revert InvalidAddress();
        Feature storage f = features[id];
        if (!f.exists) revert NotFound();
        address oldImpl = f.implementation;
        f.implementation = newImpl;
        emit FeatureUpgraded(id, oldImpl, newImpl, f.context);
    }

    function getFeature(bytes32 id) external view returns (address impl, uint8 context) {
        Feature storage f = features[id];
        if (!f.exists) revert NotFound();
        return (f.implementation, f.context);
    }

    function setService(bytes32 moduleId, string calldata serviceAlias, address addr) external onlyFeatureOwner {
        if (!features[moduleId].exists) revert ModuleNotRegistered();
        if (addr == address(0)) revert InvalidAddress();
        bytes32 serviceId = keccak256(bytes(serviceAlias));
        moduleServices[moduleId][serviceId] = addr;
        emit ServiceRegistered(serviceId, addr, moduleId);
        emit ModuleRegistered(moduleId, serviceAlias, addr);
    }

    function getService(bytes32 moduleId, string calldata serviceAlias) external view returns (address) {
        return moduleServices[moduleId][keccak256(bytes(serviceAlias))];
    }
}
