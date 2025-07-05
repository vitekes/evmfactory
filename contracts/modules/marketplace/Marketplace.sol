// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../../interfaces/ICoreKernel.sol';
import '../../interfaces/IGateway.sol';
import '../../interfaces/IPriceOracle.sol';
import '../../shared/AccessManaged.sol';
import '../../interfaces/IEventRouter.sol';
import '../../interfaces/IEventPayload.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import '../../lib/SignatureLib.sol';
import '../../interfaces/CoreDefs.sol';
import '../../errors/Errors.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

/// @title Marketplace
/// @notice Marketplace working only with off-chain listings via signatures
contract Marketplace is AccessManaged, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    // Системные контракты
    ICoreKernel public immutable registry;
    bytes32 public immutable MODULE_ID;
    IGateway public immutable paymentGateway;

    // EIP-712 domain separator
    bytes32 public immutable DOMAIN_SEPARATOR;

    // Контроль использования подписей
    mapping(bytes32 => mapping(address => bool)) public consumed;
    mapping(bytes32 => uint256) public minSaltBySku;
    mapping(bytes32 => bool) public revokedListings;

    // Все события перенесены в EventRouter

    constructor(
        address _registry,
        address _paymentGateway,
        bytes32 moduleId
    ) AccessManaged(ICoreKernel(_registry).getCoreService(CoreDefs.SERVICE_ACCESS_CONTROL)) {
        registry = ICoreKernel(_registry);
        MODULE_ID = moduleId;
        paymentGateway = IGateway(_paymentGateway);

        // Создаем EIP-712 domain separator для подписей
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(uint256 chainId,address verifyingContract)'),
                block.chainid,
                address(this)
            )
        );
    }

    /// @notice Универсальный метод покупки товара по офф-чейн листингу
    /// @param listing Структура листинга
    /// @param sellerSignature Подпись продавца
    /// @param paymentToken Предпочитаемый токен для оплаты (0 для использования валюты листинга)
    /// @param maxPaymentAmount Максимальная сумма, которую готов заплатить пользователь (для защиты от изменения курса)
    function buy(
        SignatureLib.Listing calldata listing,
        bytes calldata sellerSignature,
        address paymentToken,
        uint256 maxPaymentAmount
    ) external nonReentrant {
        // Базовые проверки перед дорогими операциями
        if (listing.price == 0) revert InvalidArgument();
        if (listing.seller == address(0)) revert ZeroAddress();

        // Вычисляем хэш листинга один раз и переиспользуем
        bytes32 buyListingHash = hashListing(listing);

        // Проверка валидности листинга (включает проверку подписи последним шагом)
        _validateListing(listing, sellerSignature, buyListingHash);

        // Отмечаем листинг как использованный для этого покупателя
        consumed[buyListingHash][msg.sender] = true;

        // Определяем токен и сумму для платежа (дешевая операция)
        address actualPaymentToken = paymentToken == address(0) ? listing.token : paymentToken;
        uint256 paymentAmount = listing.price;

        // Convert amount if payment token differs from listing token
        if (actualPaymentToken != listing.token) {
            // Check token pair support
            if (!paymentGateway.isPairSupported(MODULE_ID, listing.token, actualPaymentToken)) {
                revert UnsupportedPair();
            }

            // Calculate amount in selected currency
            paymentAmount = paymentGateway.convertAmount(MODULE_ID, listing.token, actualPaymentToken, listing.price);
            if (paymentAmount == 0) revert InvalidPrice();

            // Verify payment amount doesn't exceed maximum limit
            if (maxPaymentAmount > 0 && paymentAmount > maxPaymentAmount) {
                revert PriceExceedsMaximum();
            }
        }

        // Cache addresses to reduce storage reads
        address buyer = msg.sender;
        address seller = listing.seller;

        // Cache if token is native to avoid multiple calls
        bool isNativeToken = actualPaymentToken == address(0) ||
            actualPaymentToken == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

        uint256 netAmount;
        if (isNativeToken) {
            // Process payment with native currency
            netAmount = paymentGateway.processPayment{value: paymentAmount}(
                MODULE_ID,
                address(0), // Use zero address for native currency
                buyer,
                paymentAmount,
                '' // Empty signature for direct payments
            );

            // Transfer native currency to seller
            (bool success, ) = payable(seller).call{value: netAmount}('');
            if (!success) revert RefundDisabled();
        } else {
            // Process payment with ERC20 token
            netAmount = paymentGateway.processPayment(
                MODULE_ID,
                actualPaymentToken,
                buyer,
                paymentAmount,
                '' // Empty signature for direct payments
            );

            // Transfer funds to seller using cached addresses
            IERC20(actualPaymentToken).safeTransfer(seller, netAmount);
        }

        // Отправляем событие через EventRouter
        address buyEventRouter = registry.getModuleServiceByAlias(MODULE_ID, 'EventRouter');
        if (buyEventRouter != address(0)) {
            IEventPayload.MarketplaceEvent memory buyEventData = IEventPayload.MarketplaceEvent({
                sku: listing.sku, // ID листинга
                seller: listing.seller, // Продавец
                buyer: msg.sender, // Покупатель
                price: listing.price, // Цена в базовом токене
                paymentToken: actualPaymentToken, // Валюта платежа
                paymentAmount: paymentAmount, // Сумма платежа
                timestamp: block.timestamp, // Время продажи
                listingHash: buyListingHash, // Хэш листинга
                version: 1 // Версия события
            });
            IEventRouter(buyEventRouter).route(IEventRouter.EventKind.MarketplaceSale, abi.encode(buyEventData));
        }
    }

    /// @notice Получение цены в предпочитаемой пользователем валюте
    /// @param listing Структура листинга
    /// @param preferredCurrency Предпочитаемая валюта пользователя
    /// @return price Цена в выбранной валюте
    function getPriceInPreferredCurrency(
        SignatureLib.Listing calldata listing,
        address preferredCurrency
    ) external view returns (uint256 price) {
        // Если валюта та же, что указана в листинге, возвращаем исходную цену
        if (listing.token == preferredCurrency) {
            return listing.price;
        }

        // Иначе получаем цену в предпочитаемой валюте
        return paymentGateway.convertAmount(MODULE_ID, listing.token, preferredCurrency, listing.price);
    }

    /// @notice Проверка валидности листинга
    /// @param listing Структура листинга
    /// @param skuOnly Проверять только SKU, без проверки конкретного листинга
    /// @return valid Валидность листинга
    function isListingValid(SignatureLib.Listing calldata listing, bool skuOnly) external view returns (bool valid) {
        // Проверка срока действия
        if (listing.expiry > 0 && listing.expiry < block.timestamp) {
            return false;
        }

        // Проверка соли (версии) для SKU
        if (listing.salt < minSaltBySku[listing.sku]) {
            return false;
        }

        if (skuOnly) {
            return true;
        }

        // Проверка отзыва конкретного листинга
        bytes32 listingHash = hashListing(listing);
        if (revokedListings[listingHash]) {
            return false;
        }

        // Проверка поддержки текущей сети
        bool chainSupported = false;
        for (uint256 i = 0; i < listing.chainIds.length; i++) {
            if (listing.chainIds[i] == block.chainid) {
                chainSupported = true;
                break;
            }
        }

        return chainSupported;
    }

    /// @notice Отзыв всех листингов с определенным SKU до указанной соли
    /// @param sku SKU товара
    /// @param minSalt Минимальная соль (все листинги с меньшей солью будут отозваны)
    function revokeBySku(bytes32 sku, uint256 minSalt) external {
        // Только продавец с предыдущими листингами может отозвать
        if (minSaltBySku[sku] > 0 && msg.sender != _getSkuSeller(sku)) {
            revert NotSeller();
        }

        minSaltBySku[sku] = minSalt;

        // Отправляем событие через EventRouter
        address revokeRouter = registry.getModuleServiceByAlias(MODULE_ID, 'EventRouter');
        IEventPayload.MarketplaceEvent memory revokeEventData = IEventPayload.MarketplaceEvent({
            sku: sku, // SKU товара
            seller: msg.sender, // Продавец
            buyer: address(0), // Покупатель (нет при отзыве)
            price: 0, // Цена (нет при отзыве)
            paymentToken: address(0), // Валюта платежа (нет при отзыве)
            paymentAmount: 0, // Сумма платежа (нет при отзыве)
            timestamp: block.timestamp, // Время отзыва
            listingHash: bytes32(0), // Хеш листинга (0 для отзыва по SKU)
            version: 1 // Версия события
        });
        // Используем правильный тип события для отзыва листинга
        IEventRouter(revokeRouter).route(IEventRouter.EventKind.ListingRevoked, abi.encode(revokeEventData));
    }

    /// @notice Отзыв конкретного листинга
    /// @param listing Структура листинга
    /// @param sellerSignature Подпись продавца
    function revokeListing(SignatureLib.Listing calldata listing, bytes calldata sellerSignature) external {
        // Сначала проверяем дешевые условия
        if (listing.seller == address(0)) revert ZeroAddress();

        // Проверяем, не является ли вызывающий адрес продавцом (самый дешевый путь)
        if (msg.sender == listing.seller) {
            // Если вызывает продавец, можно отозвать без проверки подписи
            bytes32 currentListingHash = hashListing(listing);
            revokedListings[currentListingHash] = true;

            // Эмитируем событие и выходим из функции
            address router = registry.getModuleServiceByAlias(MODULE_ID, 'EventRouter');
            IEventPayload.MarketplaceEvent memory eventData = IEventPayload.MarketplaceEvent({
                sku: listing.sku, // SKU товара
                seller: listing.seller, // Продавец
                buyer: address(0), // Покупатель (нет при отзыве)
                price: 0, // Цена (нет при отзыве)
                paymentToken: address(0), // Валюта платежа (нет при отзыве)
                paymentAmount: listing.salt, // Используем это поле для передачи salt
                timestamp: block.timestamp, // Время отзыва
                listingHash: currentListingHash, // Хеш листинга
                version: 1 // Версия события
            });
            IEventRouter(router).route(IEventRouter.EventKind.ListingRevoked, abi.encode(eventData));
            return;
        }

        // Если вызывает не продавец, необходима проверка подписи
        bytes32 listingHash = hashListing(listing);

        // Проверяем подпись
        if (sellerSignature.length == 0) revert InvalidSignature();
        address signer = ECDSA.recover(listingHash, sellerSignature);
        if (signer != listing.seller) {
            revert InvalidSignature();
        }

        // Отзываем листинг
        revokedListings[listingHash] = true;

        // Отправляем событие через EventRouter
        address revokeRouter = registry.getModuleServiceByAlias(MODULE_ID, 'EventRouter');
        IEventPayload.MarketplaceEvent memory revokeEventData = IEventPayload.MarketplaceEvent({
            sku: listing.sku, // SKU товара
            seller: listing.seller, // Продавец
            buyer: address(0), // Покупатель (нет при отзыве)
            price: 0, // Цена (нет при отзыве)
            paymentToken: address(0), // Валюта платежа (нет при отзыве)
            paymentAmount: listing.salt, // Используем это поле для передачи salt
            timestamp: block.timestamp, // Время отзыва
            listingHash: listingHash, // Хеш листинга
            version: 1 // Версия события
        });
        // Используем правильный тип события для отзыва листинга
        IEventRouter(revokeRouter).route(IEventRouter.EventKind.ListingRevoked, abi.encode(revokeEventData));
    }

    /// @notice Хэширование листинга для проверки подписи
    /// @param listing Структура листинга
    /// @return Хэш листинга с доменом
    function hashListing(SignatureLib.Listing calldata listing) public view returns (bytes32) {
        return SignatureLib.hashListing(listing, DOMAIN_SEPARATOR);
    }

    /// @dev Проверка валидности листинга
    function _validateListing(
        SignatureLib.Listing calldata listing,
        bytes calldata sellerSignature,
        bytes32 listingHash
    ) internal view {
        // Оптимизированная последовательность проверок - начинаем с самых дешевых

        // 1. Сначала проверяем, не использован ли листинг этим покупателем (дешевая операция)
        if (consumed[listingHash][msg.sender]) {
            revert AlreadyPurchased();
        }

        // 2. Проверка срока действия (дешевая операция с легким доступом к хранилищу)
        if (listing.expiry > 0 && listing.expiry < block.timestamp) {
            revert Expired();
        }

        // 3. Проверка отзыва всех листингов с этим SKU (дешевая операция с одним доступом к хранилищу)
        if (listing.salt < minSaltBySku[listing.sku]) {
            revert Expired();
        }

        // 4. Проверка отзыва конкретного листинга (одно обращение к хранилищу)
        if (revokedListings[listingHash]) {
            revert Expired();
        }

        // 5. Проверка поддержки текущей сети (оптимизированный цикл)
        uint256 chainsLen = listing.chainIds.length;
        bool chainSupported = false;
        for (uint256 i = 0; i < chainsLen; i++) {
            if (listing.chainIds[i] == block.chainid) {
                chainSupported = true;
                break;
            }
        }
        if (!chainSupported) {
            revert InvalidChain();
        }

        // 6. Проверка подписи (самая дорогая операция - выполняем в последнюю очередь)
        if (ECDSA.recover(listingHash, sellerSignature) != listing.seller) {
            revert InvalidSignature();
        }
    }

    /// @dev Получение продавца для SKU (для проверки прав отзыва)
    function _getSkuSeller(bytes32 /* sku */) internal pure returns (address) {
        // Примечание: в текущей реализации этот метод всегда возвращает нулевой адрес,
        // что означает, что ни один адрес не имеет прав на отзыв SKU (кроме случая, когда minSaltBySku[sku] == 0).
        // В реальной реализации здесь нужно использовать логику для определения продавца SKU.
        // Например, можно хранить первого создателя листинга для SKU или использовать админский список.

        // Временная реализация для тестирования - первый вызов ревокации от любого адреса будет работать
        return address(0);
    }

    /// @notice Allows the contract to receive ETH (required for native currency payments)
    receive() external payable {}

    /// @notice Fallback function to reject unintended calls with ETH
    fallback() external payable {
        revert('Use buy() for purchases');
    }
}
