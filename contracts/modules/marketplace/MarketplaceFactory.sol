// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../../shared/BaseFactory.sol';
import './Marketplace.sol';
import '../../interfaces/CoreDefs.sol';

contract MarketplaceFactory is BaseFactory {
    event MarketplaceCreated(address indexed creator, address marketplace);

    constructor(
        address registry,
        address paymentGateway
    ) BaseFactory(registry, paymentGateway, CoreDefs.MARKETPLACE_MODULE_ID) {}

    /// @notice Создает новый экземпляр маркетплейса
    /// @return m Адрес созданного маркетплейса
    function createMarketplace() external onlyFactoryAdmin nonReentrant returns (address m) {
        // Проверяем платежный шлюз
        if (paymentGateway == address(0)) revert PaymentGatewayNotRegistered();

        // Создаем ID для нового маркетплейса
        bytes32 instanceId = _generateInstanceId('Marketplace');

        // Регистрируем новый экземпляр
        registry.registerFeature(instanceId, address(this), 1);

        // Настраиваем сервисы для экземпляра
        _copyServiceIfExists(instanceId, 'Validator');
        _copyServiceIfExists(instanceId, 'PriceOracle');
        registry.setModuleServiceAlias(instanceId, 'PaymentGateway', paymentGateway);

        // Создаем маркетплейс
        m = address(new Marketplace(address(registry), paymentGateway, instanceId));

        // Обновляем адрес экземпляра в реестре
        registry.upgradeFeature(instanceId, m);

        emit MarketplaceCreated(msg.sender, m);
    }
}
