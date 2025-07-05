// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '../errors/Errors.sol';
import '../interfaces/IEventRouter.sol';
import '../interfaces/IEventPayload.sol';
import '../interfaces/IRegistry.sol';
import '../interfaces/CoreDefs.sol';

contract AccessControlCenter is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    // Roles
    bytes32 public constant FEATURE_OWNER_ROLE = keccak256('FEATURE_OWNER_ROLE');
    bytes32 public constant OPERATOR_ROLE = keccak256('OPERATOR_ROLE');
    bytes32 public constant RELAYER_ROLE = keccak256('RELAYER_ROLE');
    bytes32 public constant MODULE_ROLE = keccak256('MODULE_ROLE');
    /// Role for automated keepers/cron jobs
    bytes32 public constant AUTOMATION_ROLE = keccak256('AUTOMATION_ROLE');
    /// Role for managing token validators
    bytes32 public constant GOVERNOR_ROLE = keccak256('GOVERNOR_ROLE');

    /// @notice Address holding the DEFAULT_ADMIN_ROLE
    address public adminAddr;

    /// @notice Registry contract reference
    IRegistry public registry;

    function initialize(address admin, address registryAddress) public initializer {
        if (admin == address(0)) revert InvalidAddress();
        __AccessControl_init();
        __UUPSUpgradeable_init();
        adminAddr = admin;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        if (registryAddress != address(0)) {
            registry = IRegistry(registryAddress);
        }
    }

    /// @notice Allows the owner to delegate multiple roles to an account
    /// @param account Target address
    /// @param roles Roles to grant
    function grantMultipleRoles(address account, bytes32[] calldata roles) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < roles.length; i++) {
            _grantRole(roles[i], account);
            _emitRoleGrantedEvent(roles[i], account, msg.sender);
        }
    }

    /// @notice Helper to check if an account has any of the provided roles
    /// @param account Address to check
    /// @param roles List of roles
    /// @return True if the account has at least one role
    function hasAnyRole(address account, bytes32[] memory roles) public view returns (bool) {
        for (uint256 i = 0; i < roles.length; i++) {
            if (hasRole(roles[i], account)) {
                return true;
            }
        }
        return false;
    }

    /// @notice Set registry address
    /// @param registryAddress New registry address
    function setRegistry(address registryAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (registryAddress == address(0)) revert InvalidAddress();
        registry = IRegistry(registryAddress);
    }

    /// @dev Get event router
    /// @return router Event router address or address(0) if not available
    function _getEventRouter() internal view returns (address router) {
        if (address(registry) != address(0)) {
            router = registry.getCoreService(CoreDefs.SERVICE_EVENT_ROUTER);
        }
        return router;
    }

    /// @dev Emit role granted event through EventRouter
    /// @param role Role identifier
    /// @param account Account address
    /// @param sender Sender address
    function _emitRoleGrantedEvent(bytes32 role, address account, address sender) internal {
        // Отправляем через EventRouter если доступен
        address router = _getEventRouter();
        if (router != address(0)) {
            // Для события регистрации пользователя используем структуру ServiceEvent
            // поскольку основная информация - это роль и аккаунт
            IEventPayload.ServiceEvent memory eventData = IEventPayload.ServiceEvent({
                serviceId: role, // Идентификатор роли
                serviceAddress: account, // Адрес аккаунта
                moduleId: bytes32(uint256(uint160(sender))), // Преобразуем sender в bytes32
                version: 1
            });

            IEventRouter(router).route(IEventRouter.EventKind.UserRegistered, abi.encode(eventData));
        }
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newImplementation == address(0)) revert InvalidImplementation();
    }

    uint256[49] private __gap;
}
