// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../../core/CoreSystem.sol';
import '../../core/CoreDefs.sol';
import '../../errors/Errors.sol';

/// @title Discount Manager
/// @notice Управляет скидками для товаров в маркетплейсе
contract DiscountManager {
    // Core system reference
    CoreSystem public immutable core;
    // Module ID
    bytes32 public immutable MODULE_ID;

    /// @notice Структура скидки
    struct Discount {
        uint16 discountPercent; // 0-10000, где 10000 = 100%
        uint64 startTime;
        uint64 endTime;
        bool active;
    }

    // Скидки по SKU товаров
    mapping(bytes32 => Discount) public skuDiscounts;

    // События
    event DiscountSet(
        bytes32 indexed sku,
        uint16 discountPercent,
        uint64 startTime,
        uint64 endTime,
        address indexed setter,
        bytes32 moduleId
    );

    event DiscountRemoved(bytes32 indexed sku, address indexed remover, bytes32 moduleId);

    /// @notice Убеждается, что вызывающий имеет роль администратора
    modifier onlyAdmin() {
        if (!core.hasRole(0x00, msg.sender)) revert NotAdmin();
        _;
    }

    /// @notice Убеждается, что вызывающий имеет роль владельца фичи
    modifier onlyFeatureOwner() {
        bytes32 role = CoreDefs.FEATURE_OWNER_ROLE;
        if (!core.hasRole(role, msg.sender)) revert NotFeatureOwner();
        _;
    }

    /// @notice Убеждается, что вызывающий имеет роль оператора
    modifier onlyOperator() {
        bytes32 role = CoreDefs.OPERATOR_ROLE;
        if (!core.hasRole(role, msg.sender)) revert NotOperator();
        _;
    }

    /// @notice Проверяет наличие определенной роли
    modifier onlyRole(bytes32 role) {
        if (!core.hasRole(role, msg.sender)) revert Forbidden();
        _;
    }

    /// @notice Проверяет, является ли вызывающий продавцом или администратором
    modifier onlySellerOrAdmin(address seller) {
        if (
            msg.sender != seller && !core.hasRole(0x00, msg.sender) && !core.hasRole(CoreDefs.OPERATOR_ROLE, msg.sender)
        ) {
            revert NotAuthorized();
        }
        _;
    }

    constructor(address _core, bytes32 moduleId) {
        if (_core == address(0)) revert ZeroAddress();

        core = CoreSystem(_core);
        MODULE_ID = moduleId;
    }

    /// @notice Устанавливает скидку для товара
    /// @param sku Идентификатор товара
    /// @param discountPercent Процент скидки (0-10000)
    /// @param startTime Время начала действия скидки
    /// @param endTime Время окончания действия скидки
    /// @param seller Адрес продавца товара
    function setDiscount(
        bytes32 sku,
        uint16 discountPercent,
        uint64 startTime,
        uint64 endTime,
        address seller
    ) external onlySellerOrAdmin(seller) {
        // Проверка параметров
        if (discountPercent > 10000) revert InvalidParameter();
        if (endTime <= startTime) revert InvalidParameter();

        // Установка скидки
        skuDiscounts[sku] = Discount({
            discountPercent: discountPercent,
            startTime: startTime,
            endTime: endTime,
            active: true
        });

        emit DiscountSet(sku, discountPercent, startTime, endTime, msg.sender, MODULE_ID);
    }

    /// @notice Удаляет скидку для товара
    /// @param sku Идентификатор товара
    /// @param seller Адрес продавца товара
    function removeDiscount(bytes32 sku, address seller) external onlySellerOrAdmin(seller) {
        if (!skuDiscounts[sku].active) revert NotFound();

        delete skuDiscounts[sku];

        emit DiscountRemoved(sku, msg.sender, MODULE_ID);
    }

    /// @notice Получает активную скидку для товара
    /// @param sku Идентификатор товара
    /// @return discount Информация о скидке
    function getDiscount(bytes32 sku) external view returns (Discount memory discount) {
        return skuDiscounts[sku];
    }

    /// @notice Проверяет, действует ли скидка в текущий момент
    /// @param sku Идентификатор товара
    /// @return isActive Активность скидки
    /// @return percent Процент скидки
    function isDiscountActive(bytes32 sku) external view returns (bool isActive, uint16 percent) {
        Discount memory discount = skuDiscounts[sku];

        if (discount.active && discount.startTime <= block.timestamp && discount.endTime > block.timestamp) {
            return (true, discount.discountPercent);
        }

        return (false, 0);
    }

    /// @notice Рассчитывает цену с учетом активной скидки
    /// @param sku Идентификатор товара
    /// @param originalPrice Исходная цена
    /// @return discountedPrice Цена со скидкой
    function getDiscountedPrice(bytes32 sku, uint256 originalPrice) external view returns (uint256 discountedPrice) {
        Discount memory discount = skuDiscounts[sku];

        if (discount.active && discount.startTime <= block.timestamp && discount.endTime > block.timestamp) {
            return (originalPrice * (10000 - discount.discountPercent)) / 10000;
        }

        return originalPrice;
    }
}
