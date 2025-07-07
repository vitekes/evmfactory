// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../core/interfaces/ICoreSystem.sol';
import '../payments/interfaces/IGateway.sol';
import '../errors/Errors.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import './CloneFactory.sol';
import '../shared/CoreDefs.sol';

/// @title BaseFactory
/// @notice Базовый контракт для фабрик, создающих экземпляры различных модулей
/// @dev Предоставляет общую функциональность для всех фабрик
abstract contract BaseFactory is CloneFactory, ReentrancyGuard {
    /// @notice Ссылка на ядро системы
    ICoreSystem public immutable core;

    /// @notice Ссылка на шлюз платежей
    address public immutable paymentGateway;

    /// @notice Идентификатор модуля в системе
    bytes32 public immutable MODULE_ID;

    /// @notice Счетчик для дополнительной энтропии
    uint256 private _instanceCounter;

    /// @notice Инициализирует базовую фабрику
    /// @param _core Адрес ядра системы
    /// @param _paymentGateway Адрес платежного шлюза
    /// @param moduleId Идентификатор модуля
    constructor(address _core, address _paymentGateway, bytes32 moduleId) {
        if (_core == address(0)) revert InvalidAddress();
        if (_paymentGateway == address(0)) revert InvalidAddress();
        if (moduleId == bytes32(0)) revert InvalidAddress();

        core = ICoreSystem(_core);
        paymentGateway = _paymentGateway;
        MODULE_ID = moduleId;

        // Проверка, зарегистрирован ли модуль
        try core.getFeature(moduleId) returns (address, uint8) {
            // Если модуль зарегистрирован, регистрируем платежный шлюз
            try core.setModuleServiceAlias(moduleId, "PaymentGateway", _paymentGateway) {
                // успешно
            } catch {
                // обработка ошибок может быть добавлена через события
            }
        } catch {
            // модуль будет зарегистрирован позже
        }
    }

    /// @notice Убеждается, что вызывающий имеет права администратора фабрики
    modifier onlyFactoryAdmin() {
        bytes32 FEATURE_OWNER_ROLE = keccak256('FEATURE_OWNER_ROLE');
        if (!core.hasRole(FEATURE_OWNER_ROLE, msg.sender) &&
        !core.hasRole(0x00, msg.sender)) {
            revert NotFeatureOwner();
        }
        _;
    }

    /// @dev Копирует сервис из основного модуля в экземпляр, если сервис существует
    /// @param instanceId Идентификатор экземпляра
    /// @param serviceName Имя сервиса
    /// @return Адрес скопированного сервиса или address(0), если сервиса не существует
    function _copyServiceIfExists(bytes32 instanceId, string memory serviceName) internal returns (address) {
        // Проверка параметров
        if (instanceId == bytes32(0)) revert InvalidAddress();
        if (bytes(serviceName).length == 0) revert InvalidServiceName();

        // Получаем сервис и сразу проверяем на 0
        address service = core.getModuleServiceByAlias(MODULE_ID, serviceName);
        if (service != address(0)) {
            // Вызываем core только когда это действительно необходимо
            core.setModuleServiceAlias(instanceId, serviceName, service);
        }
        return service;
    }

    /// @notice Генерирует уникальный идентификатор для экземпляра
    /// @param prefix Префикс для идентификатора
    /// @return Уникальный идентификатор
    function _generateInstanceId(string memory prefix) internal returns (bytes32) {
        // Увеличиваем счетчик для дополнительной энтропии
        _instanceCounter++;

        // Оптимизированная версия с улучшенной энтропией
        return keccak256(
            abi.encodePacked(
                bytes32(bytes(prefix)), // Фиксированный размер 32 байта экономит газ
                uint160(address(this)), // Напрямую используем uint160
                block.timestamp,
                block.prevrandao,
                _instanceCounter, // Добавляем инкрементирующийся счетчик
                blockhash(block.number - 1) // Используем хэш предыдущего блока для дополнительной энтропии
            )
        );
    }
}
