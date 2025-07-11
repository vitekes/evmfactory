// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './interfaces/IPaymentGatewayFactory.sol';
import './interfaces/IPaymentFactory.sol';
import './PaymentGateway.sol';
import '@openzeppelin/contracts/access/AccessControl.sol';
import '@openzeppelin/contracts/proxy/Clones.sol';

/// @title PaymentGatewayFactory
/// @notice Фабрика для создания экземпляров платежного шлюза
/// @dev Использует паттерн клонирования (EIP-1167) для экономии газа
contract PaymentGatewayFactory is IPaymentGatewayFactory, IPaymentFactory, AccessControl {
    using Clones for address;

    // Constants
    bytes32 public constant FACTORY_ADMIN_ROLE = keccak256('FACTORY_ADMIN_ROLE');

    // State variables
    address public immutable coreSystem;
    address public immutable processorRegistry;
    address public immutable implementation;

    // Mapping for module to gateway instances
    mapping(bytes32 => address) public moduleGateways;
    mapping(bytes32 => GatewayConfig) public gatewayConfigs;

    // Events
    event GatewayCreated(bytes32 indexed moduleId, address gateway);
    event GatewayConfigUpdated(bytes32 indexed moduleId, GatewayConfig config);

    /**
     * @dev Конструктор инициализирует фабрику с необходимыми зависимостями
     * @param _coreSystem Адрес системы ядра
     * @param _processorRegistry Адрес реестра процессоров
     */
    constructor(address _coreSystem, address _processorRegistry) {
        require(_coreSystem != address(0), 'PaymentGatewayFactory: core system is zero address');
        require(_processorRegistry != address(0), 'PaymentGatewayFactory: processor registry is zero address');

        coreSystem = _coreSystem;
        processorRegistry = _processorRegistry;

        // Деплоим имплементацию шлюза для последующего клонирования
        implementation = address(new PaymentGateway(_coreSystem, _processorRegistry));

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(FACTORY_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Создать экземпляр платежного шлюза для модуля
     * @param moduleId Идентификатор модуля
     * @param config Начальная конфигурация шлюза
     * @return gateway Адрес созданного шлюза
     */
    function createGateway(
        bytes32 moduleId,
        GatewayConfig calldata config
    ) external override onlyRole(FACTORY_ADMIN_ROLE) returns (address gateway) {
        require(moduleGateways[moduleId] == address(0), 'PaymentGatewayFactory: gateway already exists for module');
        require(config.gatewayFeeRecipient != address(0), 'PaymentGatewayFactory: fee recipient is zero address');

        // Клонируем имплементацию шлюза
        gateway = implementation.clone();

        // Инициализируем шлюз с параметрами для модуля
        PaymentGateway paymentGateway = PaymentGateway(gateway);

        // Сохраняем ссылку на созданный шлюз
        moduleGateways[moduleId] = gateway;
        gatewayConfigs[moduleId] = config;

        // Настраиваем процессоры по умолчанию
        _configureDefaultProcessors(paymentGateway, moduleId, config.defaultProcessors);

        // Передаем права администратора шлюза фабрике
        bytes32 PAYMENT_ADMIN_ROLE = paymentGateway.PAYMENT_ADMIN_ROLE();
        bytes32 PROCESSOR_MANAGER_ROLE = paymentGateway.PROCESSOR_MANAGER_ROLE();
        bytes32 DEFAULT_ADMIN_ROLE = 0x00;

        // Настраиваем роли для шлюза
        AccessControl(gateway).grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        AccessControl(gateway).grantRole(PAYMENT_ADMIN_ROLE, msg.sender);
        AccessControl(gateway).grantRole(PROCESSOR_MANAGER_ROLE, msg.sender);

        emit GatewayCreated(moduleId, gateway);
        return gateway;
    }

    /**
     * @notice Получить экземпляр шлюза для модуля
     * @param moduleId Идентификатор модуля
     * @return gateway Адрес шлюза
     */
    function getGateway(bytes32 moduleId) external view override returns (address gateway) {
        return moduleGateways[moduleId];
    }

    /**
     * @notice Обновить конфигурацию шлюза для модуля
     * @param moduleId Идентификатор модуля
     * @param config Новая конфигурация
     * @return success Успешность операции
     */
    function updateGatewayConfig(
        bytes32 moduleId,
        GatewayConfig calldata config
    ) external override onlyRole(FACTORY_ADMIN_ROLE) returns (bool success) {
        address gateway = moduleGateways[moduleId];
        require(gateway != address(0), 'PaymentGatewayFactory: gateway not found for module');
        require(config.gatewayFeeRecipient != address(0), 'PaymentGatewayFactory: fee recipient is zero address');

        // Обновляем конфигурацию
        gatewayConfigs[moduleId] = config;

        // Получаем экземпляр шлюза
        PaymentGateway paymentGateway = PaymentGateway(gateway);

        // Обновляем процессоры
        _configureDefaultProcessors(paymentGateway, moduleId, config.defaultProcessors);

        emit GatewayConfigUpdated(moduleId, config);
        return true;
    }

    /**
     * @notice Получить конфигурацию шлюза для модуля
     * @param moduleId Идентификатор модуля
     * @return config Конфигурация шлюза
     */
    function getGatewayConfig(bytes32 moduleId) external view override returns (GatewayConfig memory config) {
        return gatewayConfigs[moduleId];
    }

    /**
     * @notice Получить реестр процессоров
     * @return registry Адрес реестра процессоров
     */
    function getProcessorRegistry() external view override returns (address registry) {
        return processorRegistry;
    }

    /**
     * @notice Получить имя фабрики
     * @return name Имя фабрики
     */
    function getName() external pure override returns (string memory name) {
        return 'PaymentGatewayFactory';
    }

    /**
     * @notice Получить версию фабрики
     * @return version Версия фабрики
     */
    function getVersion() external pure override returns (string memory version) {
        return '1.0.0';
    }

    /**
     * @notice Создать компонент с указанными параметрами (реализация IPaymentFactory)
     * @param id Идентификатор компонента (moduleId)
     * @param config Конфигурация в формате байтов
     * @return component Адрес созданного компонента
     */
    function createComponent(
        bytes32 id,
        bytes calldata config
    ) external override onlyRole(FACTORY_ADMIN_ROLE) returns (address component) {
        // Декодируем конфигурацию из байтов
        GatewayConfig memory gatewayConfig = abi.decode(config, (GatewayConfig));

        // Создаем шлюз с помощью существующего метода
        return createGateway(id, gatewayConfig);
    }

    /**
     * @notice Получить созданный компонент по идентификатору (реализация IPaymentFactory)
     * @param id Идентификатор компонента
     * @return component Адрес компонента
     */
    function getComponent(bytes32 id) external view override returns (address component) {
        return moduleGateways[id];
    }

    /**
     * @dev Внутренняя функция для настройки процессоров по умолчанию
     * @param gateway Экземпляр шлюза
     * @param moduleId Идентификатор модуля
     * @param processors Список процессоров по умолчанию
     */
    function _configureDefaultProcessors(
        PaymentGateway gateway,
        bytes32 moduleId,
        address[] memory processors
    ) internal {
        for (uint256 i = 0; i < processors.length; i++) {
            address processor = processors[i];
            if (processor == address(0)) continue;

            // Получаем имя процессора
            string memory processorName = IPaymentProcessor(processor).getName();

            // Проверяем, что процессор зарегистрирован
            // Если нет, регистрируем его
            if (gateway.getProcessors(moduleId).length == 0) {
                gateway.addProcessor(processor, 0);
            }

            // Настраиваем процессор для модуля
            gateway.configureProcessor(moduleId, processorName, true, '');
        }
    }
}
