// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '@openzeppelin/contracts/access/AccessControl.sol';

/// @title PaymentSystemRoleManager
/// @notice Централизованный контракт для управления ролями в платежной системе
/// @dev Управляет всеми ролями для различных компонентов системы
contract PaymentSystemRoleManager is AccessControl {
    // Глобальные административные роли
    bytes32 public constant SYSTEM_ADMIN_ROLE = keccak256('SYSTEM_ADMIN');
    bytes32 public constant PROCESSOR_ADMIN_ROLE = keccak256('PROCESSOR_ADMIN');
    bytes32 public constant MODULE_MANAGER_ROLE = keccak256('MODULE_MANAGER');

    // Специфичные роли процессоров
    bytes32 public constant FEE_COLLECTOR_ROLE = keccak256('FEE_COLLECTOR_ROLE');
    bytes32 public constant PRICE_FEEDER_ROLE = keccak256('PRICE_FEEDER_ROLE');
    bytes32 public constant DISCOUNT_MANAGER_ROLE = keccak256('DISCOUNT_MANAGER_ROLE');
    bytes32 public constant PAYMENT_ADMIN_ROLE = keccak256('PAYMENT_ADMIN_ROLE');
    bytes32 public constant PROCESSOR_MANAGER_ROLE = keccak256('PROCESSOR_MANAGER_ROLE');

    // Другие роли можно добавлять по мере необходимости

    // Маппинг для хранения специфичных ролей процессоров
    // процессор => роль => адрес => разрешение
    mapping(address => mapping(bytes32 => mapping(address => bool))) public processorRoles;

    // Событие для отслеживания изменений ролей
    event ProcessorRoleGranted(address indexed processor, bytes32 indexed role, address indexed account);
    event ProcessorRoleRevoked(address indexed processor, bytes32 indexed role, address indexed account);

    /**
     * @dev Конструктор
     */
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SYSTEM_ADMIN_ROLE, msg.sender);
        _grantRole(PROCESSOR_ADMIN_ROLE, msg.sender);
        _grantRole(MODULE_MANAGER_ROLE, msg.sender);
    }

    /**
     * @notice Проверить, имеет ли аккаунт специфичную роль для процессора
     * @param processor Адрес процессора
     * @param role Идентификатор роли
     * @param account Адрес аккаунта
     * @return hasRole Имеет ли аккаунт указанную роль
     */
    function hasProcessorRole(address processor, bytes32 role, address account) external view returns (bool) {
        return processorRoles[processor][role][account];
    }

    /**
     * @notice Предоставить специфичную роль для процессора
     * @param processor Адрес процессора
     * @param role Идентификатор роли
     * @param account Адрес аккаунта
     */
    function grantProcessorRole(
        address processor,
        bytes32 role,
        address account
    ) external onlyRole(PROCESSOR_ADMIN_ROLE) {
        require(processor != address(0), 'RoleManager: processor is zero address');
        require(account != address(0), 'RoleManager: account is zero address');

        processorRoles[processor][role][account] = true;

        emit ProcessorRoleGranted(processor, role, account);
    }

    /**
     * @notice Отозвать специфичную роль для процессора
     * @param processor Адрес процессора
     * @param role Идентификатор роли
     * @param account Адрес аккаунта
     */
    function revokeProcessorRole(
        address processor,
        bytes32 role,
        address account
    ) external onlyRole(PROCESSOR_ADMIN_ROLE) {
        require(processor != address(0), 'RoleManager: processor is zero address');
        require(account != address(0), 'RoleManager: account is zero address');

        processorRoles[processor][role][account] = false;

        emit ProcessorRoleRevoked(processor, role, account);
    }

    /**
     * @notice Проверить, имеет ли аккаунт роль в системе
     * @param role Идентификатор роли
     * @param account Адрес аккаунта
     * @return hasRole Имеет ли аккаунт указанную роль
     */
    function hasSystemRole(bytes32 role, address account) external view returns (bool) {
        return hasRole(role, account);
    }

    /**
     * @notice Предоставить глобальную системную роль
     * @param role Идентификатор роли
     * @param account Адрес аккаунта
     */
    function grantSystemRole(bytes32 role, address account) external onlyRole(SYSTEM_ADMIN_ROLE) {
        _grantRole(role, account);
    }

    /**
     * @notice Отозвать глобальную системную роль
     * @param role Идентификатор роли
     * @param account Адрес аккаунта
     */
    function revokeSystemRole(bytes32 role, address account) external onlyRole(SYSTEM_ADMIN_ROLE) {
        _revokeRole(role, account);
    }
}
