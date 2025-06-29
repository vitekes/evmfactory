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
    ) BaseFactory(registry, paymentGateway, keccak256('Marketplace')) {}

    function createMarketplace() external onlyFactoryAdmin nonReentrant returns (address m) {
        // Получаем необходимые сервисы используя строковые алиасы вместо bytes32
        address gateway = registry.getModuleServiceByAlias(MODULE_ID, "PaymentGateway");
        if (gateway == address(0)) revert PaymentGatewayNotRegistered();

        // Создаем ID для нового маркетплейса
        bytes32 instanceId = keccak256(abi.encodePacked('Marketplace:', address(this), block.timestamp));

        // Сначала регистрируем новый экземпляр (чтобы он существовал в реестре)
        registry.registerFeature(instanceId, address(this), 1);

        // Копируем сервисы из основного модуля в экземпляр используя строковые алиасы
        address validator = registry.getModuleServiceByAlias(MODULE_ID, "Validator");
        if (validator != address(0)) {
            registry.setModuleServiceAlias(instanceId, "Validator", validator);
        }
        registry.setModuleServiceAlias(instanceId, "PaymentGateway", gateway);

        // Создаем маркетплейс
        m = address(new Marketplace(address(registry), gateway, instanceId));

        // Обновляем адрес экземпляра в реестре
        registry.upgradeFeature(instanceId, m);

        emit MarketplaceCreated(msg.sender, m);
    }
}
