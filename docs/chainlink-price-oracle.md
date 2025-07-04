# Chainlink Price Oracle

## Обзор

ChainlinkPriceOracle - это контракт, который предоставляет доступ к ценам активов через фиды Chainlink. Он позволяет получать актуальные цены для конвертации между различными токенами и проверять поддержку пар токенов.

## Ключевые функции

- Получение цен из Chainlink price feeds
- Конвертация сумм между разными токенами
- Проверка свежести данных о ценах
- Управление поддерживаемыми парами токенов

## Интеграция в проект

### Конфигурация после деплоя

После деплоя контракта ChainlinkPriceOracle, необходимо настроить ценовые фиды для поддерживаемых токенов. Для этого используйте скрипт `scripts/deployments/config-price-feeds.ts`:

```bash
PRICE_ORACLE_ADDRESS=0x... npx hardhat run scripts/deployments/config-price-feeds.ts --network mainnet
```

### Добавление новых фидов

Для добавления нового ценового фида используйте функцию `setPriceFeed`:

```solidity
function setPriceFeed(
    address token,
    address priceFeed,
    address baseToken
) external;
```

Параметры:
- `token`: Адрес токена, для которого добавляется фид
- `priceFeed`: Адрес контракта Chainlink price feed
- `baseToken`: Базовый токен (обычно USDC или USDT)

### Использование в других контрактах

Для использования оракула в других контрактах получите его через Registry:

```solidity
address oracle = registry.getModuleServiceByAlias(moduleId, 'PriceOracle');
IPriceOracle priceOracle = IPriceOracle(oracle);

// Конвертация суммы из одного токена в другой
uint256 convertedAmount = priceOracle.convertAmount(fromToken, toToken, amount);
```

## Безопасность и поддержка

- Оракул проверяет свежесть данных (не старше 24 часов)
- Поддерживает только прямые фиды (без посредников)
- Требует роль GOVERNOR_ROLE для настройки фидов

## Тестирование

Для тестирования в локальной среде рекомендуется использовать MockPriceFeed вместо ChainlinkPriceOracle, который предоставляет аналогичный интерфейс без зависимости от внешних сервисов.

## Адреса фидов Chainlink

Список актуальных адресов price feeds для разных сетей можно найти в [официальной документации Chainlink](https://docs.chain.link/data-feeds/price-feeds/addresses).
