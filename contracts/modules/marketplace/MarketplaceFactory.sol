// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../../core/BaseFactory.sol';
import './Marketplace.sol';
import '../../core/CoreDefs.sol';

contract MarketplaceFactory is BaseFactory {
    event MarketplaceCreated(address indexed creator, address marketplace);

    constructor(
        address registry,
        address _paymentGateway
    ) BaseFactory(registry, _paymentGateway, CoreDefs.MARKETPLACE_MODULE_ID) {}

    /// @notice Создает новый экземпляр маркетплейса
    /// @return m Адрес созданного маркетплейса
    function createMarketplace() external onlyFactoryAdmin nonReentrant returns (address m) {
        // Создаем уникальный ID для нового маркетплейса
        bytes32 instanceId = _generateInstanceId('Marketplace');

        // Регистрируем новый экземпляр маркетплейса в core
        core.registerFeature(instanceId, address(this), 1);

        // Копируем сервисы из основного модуля
        core.setService(instanceId, 'PaymentGateway', paymentGateway);

        // Создаем новый экземпляр Marketplace, передавая ядро, платёжный шлюз и идентификатор
        m = address(new Marketplace(address(core), paymentGateway, instanceId));

        // Обновляем адрес созданного маркетплейса в реестре core
        core.upgradeFeature(instanceId, m);

        // Эмитируем событие создания маркетплейса
        emit MarketplaceCreated(msg.sender, m);
    }
}
