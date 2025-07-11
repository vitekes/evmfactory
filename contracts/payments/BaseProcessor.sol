// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './interfaces/IPaymentProcessor.sol';
import './PaymentContextLibrary.sol';
import './PaymentSystemRoleManager.sol';
import '@openzeppelin/contracts/access/AccessControl.sol';

/// @title BaseProcessor
/// @notice Базовый абстрактный класс для процессоров платежей
/// @dev Содержит общую логику для всех процессоров платежей
abstract contract BaseProcessor is IPaymentProcessor, AccessControl {
    using PaymentContextLibrary for PaymentContextLibrary.PaymentContext;

    // Constants
    bytes32 public constant PROCESSOR_ADMIN_ROLE = keccak256('PROCESSOR_ADMIN_ROLE');

    // Общие переменные состояния
    mapping(bytes32 => bool) public moduleEnabled; // moduleId => enabled
    PaymentSystemRoleManager public roleManager;

    // События
    event ModuleConfigured(bytes32 indexed moduleId, bool enabled);
    event RoleManagerSet(address indexed roleManager);

    /**
     * @dev Конструктор базового класса
     */
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PROCESSOR_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Установить менеджер ролей
     * @param _roleManager Адрес менеджера ролей
     */
    function setRoleManager(address _roleManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_roleManager != address(0), 'BaseProcessor: role manager is zero address');
        roleManager = PaymentSystemRoleManager(_roleManager);
        emit RoleManagerSet(_roleManager);
    }

    /**
     * @dev Проверяет, имеет ли аккаунт специфичную роль для процессора
     * @param role Идентификатор роли
     * @param account Адрес аккаунта для проверки
     * @return Имеет ли аккаунт указанную роль
     */
    function _hasProcessorRole(bytes32 role, address account) internal view returns (bool) {
        // Если менеджер ролей не установлен, используем стандартную проверку AccessControl
        if (address(roleManager) == address(0)) {
            return hasRole(role, account);
        }

        // Проверяем роль в централизованном менеджере ролей
        return roleManager.hasProcessorRole(address(this), role, account) || roleManager.hasSystemRole(role, account);
    }

    /**
     * @notice Обработать контекст платежа
     * @param contextBytes Контекст платежа в байтах
     * @return result Результат обработки
     * @return updatedContext Обновленный контекст в байтах
     */
    function process(
        bytes memory contextBytes
    ) external virtual override returns (ProcessResult result, bytes memory updatedContext) {
        // Декодируем контекст
        PaymentContextLibrary.PaymentContext memory context = abi.decode(
            contextBytes,
            (PaymentContextLibrary.PaymentContext)
        );

        // Если модуль не активирован для процессора, пропускаем обработку
        if (!moduleEnabled[context.moduleId]) {
            return (ProcessResult.SKIPPED, contextBytes);
        }

        // Проверяем применимость
        if (!_isApplicableInternal(context)) {
            context = PaymentContextLibrary.addProcessorResult(context, getName(), uint8(ProcessResult.SKIPPED));
            return (ProcessResult.SKIPPED, abi.encode(context));
        }

        // Вызываем реализацию конкретного процессора
        return _processInternal(context);
    }

    /**
     * @notice Получить имя процессора
     * @return name Имя процессора
     */
    function getName() public pure virtual override returns (string memory name);

    /**
     * @notice Получить версию процессора
     * @return version Версия процессора
     */
    function getVersion() public pure virtual override returns (string memory version);

    /**
     * @notice Проверить, активен ли процессор
     * @param moduleId Идентификатор модуля
     * @return enabled Активен ли процессор для модуля
     */
    function isEnabled(bytes32 moduleId) external view override returns (bool enabled) {
        return moduleEnabled[moduleId];
    }

    /**
     * @notice Настроить процессор для модуля
     * @param moduleId Идентификатор модуля
     * @param config Конфигурация в виде байтов (ожидается: bool enabled)
     * @return success Успешность настройки
     */
    function configure(bytes32 moduleId, bytes calldata config) external virtual override returns (bool success) {
        // Проверяем роль с учетом централизованного управления ролями
        require(
            _hasProcessorRole(PROCESSOR_ADMIN_ROLE, msg.sender) || hasRole(PROCESSOR_ADMIN_ROLE, msg.sender),
            'BaseProcessor: caller is not a processor admin'
        );

        if (config.length > 0) {
            bool enabled = abi.decode(config, (bool));
            moduleEnabled[moduleId] = enabled;
            emit ModuleConfigured(moduleId, enabled);

            // Если требуется дополнительная настройка, потомки могут переопределить
            _configureInternal(moduleId, config);
        }

        return true;
    }

    /**
     * @notice Проверить, применим ли процессор к контексту
     * @param contextBytes Контекст платежа в байтах
     * @return applicable Применим ли процессор
     */
    function isApplicable(bytes memory contextBytes) external view virtual override returns (bool applicable) {
        PaymentContextLibrary.PaymentContext memory context = abi.decode(
            contextBytes,
            (PaymentContextLibrary.PaymentContext)
        );

        // Базовая проверка - модуль должен быть активирован
        if (!moduleEnabled[context.moduleId]) return false;

        // Вызываем внутреннюю реализацию для конкретного процессора
        return _isApplicableInternal(context);
    }

    /**
     * @dev Внутренняя реализация логики обработки контекста для конкретного процессора
     * @param context Контекст платежа
     * @return result Результат обработки
     * @return updatedContext Обновленный контекст в байтах
     */
    function _processInternal(
        PaymentContextLibrary.PaymentContext memory context
    ) internal virtual returns (ProcessResult result, bytes memory updatedContext);

    /**
     * @dev Внутренняя реализация проверки применимости для конкретного процессора
     * @param context Контекст платежа
     * @return applicable Применим ли процессор
     */
    function _isApplicableInternal(
        PaymentContextLibrary.PaymentContext memory context
    ) internal view virtual returns (bool applicable);

    /**
     * @dev Внутренняя функция для дополнительной настройки в конкретных процессорах
     * @param moduleId Идентификатор модуля
     * @param config Конфигурация
     */
    function _configureInternal(bytes32 moduleId, bytes calldata config) internal virtual {
        // По умолчанию ничего не делаем, конкретные процессоры могут переопределить
    }

    /**
     * @dev Вспомогательная функция для создания ошибки обработки
     * @param context Исходный контекст
     * @param errorMessage Сообщение об ошибке
     * @return Обновленный контекст с ошибкой
     */
    function _createError(
        PaymentContextLibrary.PaymentContext memory context,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
        context.state = PaymentContextLibrary.ProcessingState.FAILED;
        context.success = false;
        context.errorMessage = errorMessage;
        context = PaymentContextLibrary.addProcessorResult(context, getName(), uint8(ProcessResult.FAILED));
        return abi.encode(context);
    }
}
