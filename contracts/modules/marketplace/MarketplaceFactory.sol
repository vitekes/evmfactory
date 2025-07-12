// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../../core/BaseFactory.sol';
import './Marketplace.sol';
import '../../core/CoreDefs.sol';

contract MarketplaceFactory is BaseFactory {
    event MarketplaceCreated(address indexed creator, address marketplace);

    // Адрес платёжного шлюза, используемого для всех маркетплейсов, созданных этой фабрикой
    address public immutable paymentGateway;

    constructor(
        address registry,
        address _paymentGateway
    ) BaseFactory(registry, _paymentGateway, CoreDefs.MARKETPLACE_MODULE_ID) {
        if (_paymentGateway == address(0)) revert PaymentGatewayNotRegistered();
        paymentGateway = _paymentGateway;
    }

    /// @notice Создает новый экземпляр маркетплейса
    /// @return m Адрес созданного маркетплейса
    function createMarketplace() external onlyFactoryAdmin nonReentrant returns (address m) {
        // Создаем уникальный ID для нового маркетплейса
        bytes32 instanceId = _generateInstanceId('Marketplace');

        // Регистрируем новый экземпляр маркетплейса в core
        core.registerFeature(instanceId, address(this), 1);

        // Создаем и инициализируем платёжный шлюз и оркестратор для маркетплейса
        PaymentOrchestrator orchestrator = new PaymentOrchestrator();
        PaymentGateway gateway = new PaymentGateway(address(orchestrator));

        // Регистрируем оркестратор и шлюз в core как сервисы
        core.setService(instanceId, 'PaymentOrchestrator', address(orchestrator));
        core.setService(instanceId, 'PaymentGateway', address(gateway));

        // Инициализируем процессоры платёжного шлюза (валидатор, дисконт, комиссия, оракул и т.д.)
        // Пример инициализации процессоров (можно расширить по необходимости)
        // Здесь предполагается, что есть методы для регистрации процессоров в оркестраторе или реестре
        // Для упрощения примера пропущена конкретная реализация

        // Создаем новый экземпляр Marketplace, передавая core, адрес платёжного шлюза и instanceId
        m = address(new Marketplace(address(core), address(gateway), instanceId));

        // Обновляем адрес созданного маркетплейса в реестре core
        core.upgradeFeature(instanceId, m);

        // Эмитируем событие создания маркетплейса
        emit MarketplaceCreated(msg.sender, m);
    }
}
