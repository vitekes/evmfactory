# Chainlink Price Oracle

Этот документ описывает, как использовать Chainlink Price Oracle для поддержки мультитокенных платежей в проекте.

## Обзор

Oracle предоставляет следующие возможности:
- Получение актуальных цен токенов через Chainlink Price Feeds
- Конвертация сумм между разными токенами
- Проверка поддержки пар токенов
- Проверка актуальности данных о ценах

## Интеграция с модулями

### Marketplace

**Создание листинга с поддержкой разных токенов**

```solidity
// Базовая цена в USDC
address baseToken = USDC_ADDRESS;
uint256 basePrice = 100 * 10**6; // 100 USDC

// Принимаемые токены
address[] memory acceptedTokens = new address[](3);
acceptedTokens[0] = USDC_ADDRESS;
acceptedTokens[1] = WETH_ADDRESS;
acceptedTokens[2] = WBTC_ADDRESS;

// Создание листинга
uint256 listingId = marketplace.list(baseToken, basePrice, acceptedTokens);
```

**Покупка с использованием альтернативного токена**

```solidity
// Получение стоимости в WETH
uint256 wethCost = marketplace.getPaymentAmount(listingId, WETH_ADDRESS);
console.log(`Цена в WETH: ${wethCost}`);

// Покупка за WETH
marketplace.buyWithToken(listingId, WETH_ADDRESS);
```

### Subscription Manager

**Подписка с использованием альтернативного токена**

```solidity
// План подписки (цена в USDC)
SignatureLib.Plan memory plan = SignatureLib.Plan({
    chainIds: [1],
    price: 10 * 10**6, // 10 USDC
    period: 30 days,
    token: USDC_ADDRESS,
    merchant: merchantAddress,
    salt: 123,
    expiry: 0
});

// Получение стоимости в WETH
uint256 wethCost = subscriptionManager.getPlanPaymentInToken(plan, WETH_ADDRESS);

// Подписка с оплатой в WETH
subscriptionManager.subscribeWithToken(plan, merchantSignature, permitSignature, WETH_ADDRESS);
```

## Настройка Oracle

### Регистрация Oracle в Registry

```typescript
// В скрипте развертывания
const priceOracleFactory = await PriceOracleFactory.deploy(registry.address, ethers.ZeroAddress);

// Регистрируем фабрику в Registry
const MODULE_ID = ethers.keccak256(ethers.toUtf8Bytes("OracleProcessor.sol"));
await registry.registerFeature(MODULE_ID, priceOracleFactory.address, 1);

// Создаем экземпляр Oracle
await priceOracleFactory.createPriceOracle();
```

### Настройка Price Feeds

```typescript
// Настройка Price Feeds для Ethereum
const USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
const WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
const ETH_USD_FEED = "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419";

// Устанавливаем Price Feed для ETH с базовой валютой USDC
await priceOracle.setPriceFeed(WETH, ETH_USD_FEED, USDC);
```

## Безопасность

- Oracle проверяет актуальность данных (не старше MAX_PRICE_AGE)
- Проверяется корректность раундов в Price Feed
- Поддерживаются только положительные цены
- При возникновении проблем с данными операции отменяются

## Тестирование

Для тестирования используйте MockChainlinkPriceFeed:

```typescript
// Создание мока Price Feed
const mockPriceFeed = await MockChainlinkPriceFeed.deploy(
  8, // decimals
  "ETH / USD", // description
  2500 * 10**8 // цена $2500 с 8 десятичными знаками
);

// Настройка в Oracle
await priceOracle.setPriceFeed(wethToken.address, mockPriceFeed.address, usdcToken.address);
```
