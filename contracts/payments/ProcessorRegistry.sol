// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './interfaces/IProcessorRegistry.sol';
import './interfaces/IPaymentProcessor.sol';
import '@openzeppelin/contracts/access/AccessControl.sol';

/// @title ProcessorRegistry
/// @notice Реестр обработчиков платежей
/// @dev Управляет регистрацией и последовательностью обработчиков
contract ProcessorRegistry is IProcessorRegistry, AccessControl {
    // Constants
    bytes32 public constant REGISTRY_ADMIN_ROLE = keccak256('REGISTRY_ADMIN_ROLE');

    // State variables
    address public immutable coreSystem;
    mapping(string => address) private processorsByName;
    mapping(bytes32 => address[]) private moduleProcessors;
    mapping(bytes32 => mapping(string => bool)) private moduleProcessorEnabled;

    // Events
    event ProcessorRegistered(address indexed processor, string name, uint256 position);
    event ProcessorRemoved(string indexed name, address indexed processor);
    event ProcessorOrderUpdated(bytes32 indexed moduleId, string[] newOrder);
    event ProcessorStatusChanged(bytes32 indexed moduleId, string indexed name, bool enabled);

    /**
     * @dev Конструктор инициализирует реестр
     * @param _coreSystem Адрес системы ядра
     */
    constructor(address _coreSystem) {
        require(_coreSystem != address(0), 'ProcessorRegistry: core system is zero address');

        coreSystem = _coreSystem;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(REGISTRY_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Зарегистрировать новый процессор
     * @param processor Адрес процессора
     * @param position Позиция в цепочке (0 - в конец)
     * @return success Успешность операции
     */
    function registerProcessor(
        address processor,
        uint256 position
    ) external override onlyRole(REGISTRY_ADMIN_ROLE) returns (bool success) {
        require(processor != address(0), 'ProcessorRegistry: processor is zero address');

        // Получаем имя процессора
        string memory name = IPaymentProcessor(processor).getName();
        require(bytes(name).length > 0, 'ProcessorRegistry: processor name is empty');

        // Проверяем, что процессор с таким именем еще не зарегистрирован
        require(processorsByName[name] == address(0), 'ProcessorRegistry: processor already registered');

        // Сохраняем процессор в реестре
        processorsByName[name] = processor;

        emit ProcessorRegistered(processor, name, position);
        return true;
    }

    /**
     * @notice Удалить процессор из реестра
     * @param processorName Имя процессора
     * @return success Успешность операции
     */
    function removeProcessor(
        string calldata processorName
    ) external override onlyRole(REGISTRY_ADMIN_ROLE) returns (bool success) {
        require(bytes(processorName).length > 0, 'ProcessorRegistry: processor name is empty');

        address processor = processorsByName[processorName];
        require(processor != address(0), 'ProcessorRegistry: processor not found');

        // Удаляем процессор из реестра
        delete processorsByName[processorName];

        emit ProcessorRemoved(processorName, processor);
        return true;
    }

    /**
     * @notice Получить адрес процессора по имени
     * @param name Имя процессора
     * @return processorAddress Адрес процессора
     */
    function getProcessorByName(string calldata name) external view override returns (address processorAddress) {
        return processorsByName[name];
    }

    /**
     * @notice Получить цепочку процессоров для модуля
     * @param moduleId Идентификатор модуля
     * @return processors Массив адресов процессоров
     */
    function getProcessorChain(bytes32 moduleId) external view override returns (address[] memory processors) {
        return moduleProcessors[moduleId];
    }

    /**
     * @notice Обновить порядок процессоров для модуля
     * @param moduleId Идентификатор модуля
     * @param newOrder Новый порядок процессоров (массив имен)
     * @return success Успешность операции
     */
    function updateProcessorOrder(
        bytes32 moduleId,
        string[] calldata newOrder
    ) external override onlyRole(REGISTRY_ADMIN_ROLE) returns (bool success) {
        // Создаем новый массив для процессоров
        address[] memory newProcessors = new address[](newOrder.length);

        // Проверяем, что все процессоры существуют и заполняем массив
        for (uint256 i = 0; i < newOrder.length; i++) {
            address processor = processorsByName[newOrder[i]];
            require(processor != address(0), 'ProcessorRegistry: processor not found');
            newProcessors[i] = processor;
        }

        // Обновляем порядок процессоров
        moduleProcessors[moduleId] = newProcessors;

        emit ProcessorOrderUpdated(moduleId, newOrder);
        return true;
    }

    /**
     * @notice Включить/выключить процессор для модуля
     * @param moduleId Идентификатор модуля
     * @param processorName Имя процессора
     * @param enabled Включен/выключен
     * @return success Успешность операции
     */
    function setProcessorEnabled(
        bytes32 moduleId,
        string calldata processorName,
        bool enabled
    ) external override onlyRole(REGISTRY_ADMIN_ROLE) returns (bool success) {
        require(bytes(processorName).length > 0, 'ProcessorRegistry: processor name is empty');
        require(processorsByName[processorName] != address(0), 'ProcessorRegistry: processor not found');

        // Обновляем статус процессора
        moduleProcessorEnabled[moduleId][processorName] = enabled;

        emit ProcessorStatusChanged(moduleId, processorName, enabled);
        return true;
    }

    /**
     * @notice Проверить, включен ли процессор для модуля
     * @param moduleId Идентификатор модуля
     * @param processorName Имя процессора
     * @return enabled Статус процессора
     */
    function isProcessorEnabled(
        bytes32 moduleId,
        string calldata processorName
    ) external view override returns (bool enabled) {
        return moduleProcessorEnabled[moduleId][processorName];
    }
}
