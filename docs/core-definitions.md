# Библиотека основных определений (CoreDefs)

## Обзор

Библиотека `CoreDefs` содержит предопределенные константы для идентификаторов модулей, сервисов и других общих значений, используемых по всей системе. Использование этих констант повышает читаемость кода, снижает вероятность ошибок и обеспечивает единообразие в разных частях проекта.

## Категории констант

Библиотека разделена на несколько логических категорий:

### Идентификаторы модулей

Используются для идентификации различных модулей системы:

```solidity
bytes32 internal constant MARKETPLACE_MODULE_ID = keccak256('Marketplace');
bytes32 internal constant SUBSCRIPTION_MODULE_ID = keccak256('SubscriptionManager');
bytes32 internal constant CONTEST_MODULE_ID = keccak256('Contest');
bytes32 internal constant PRICE_ORACLE_MODULE_ID = keccak256('PriceOracle');
```

### Идентификаторы основных сервисов

Ключевые сервисы, необходимые для функционирования системы:

```solidity
bytes32 internal constant SERVICE_REGISTRY = keccak256('Registry');
bytes32 internal constant SERVICE_FEE_MANAGER = keccak256('CoreFeeManager');
bytes32 internal constant SERVICE_PAYMENT_GATEWAY = keccak256('PaymentGateway');
```

### Идентификаторы сервисов модулей

Сервисы, используемые конкретными модулями:

```solidity
bytes32 internal constant SERVICE_VALIDATOR = keccak256('Validator');
bytes32 internal constant SERVICE_PRICE_ORACLE = keccak256('PriceOracle');
bytes32 internal constant SERVICE_PERMIT2 = keccak256('Permit2');
```

### Строковые алиасы

Строковые представления идентификаторов для использования с методом `getModuleServiceByAlias`:

```solidity
string internal constant ALIAS_PAYMENT_GATEWAY = 'PaymentGateway';
string internal constant ALIAS_VALIDATOR = 'Validator';
// и т.д.
```

### Временные константы

Стандартные временные интервалы для использования в различных функциях:

```solidity
uint256 internal constant SECONDS_PER_DAY = 86400;
uint256 internal constant SECONDS_PER_WEEK = 604800;
// и т.д.
```

## Использование в коде

Пример использования констант в контрактах:

```solidity
// Вместо
address gateway = registry.getModuleServiceByAlias(MODULE_ID, 'PaymentGateway');

// Используйте
address gateway = registry.getModuleServiceByAlias(MODULE_ID, CoreDefs.ALIAS_PAYMENT_GATEWAY);
```

## Преимущества использования CoreDefs

1. **Предотвращение ошибок**: Опечатки в строковых литералах могут вызвать трудноуловимые ошибки. Константы выявляют такие ошибки на этапе компиляции.

2. **Улучшенная читаемость**: Наименования констант более описательны, чем их значения.

3. **Простота обслуживания**: Изменение значения в одном месте автоматически применяется во всех местах использования.

4. **Документированность**: Константы включают комментарии, объясняющие их назначение.

5. **Оптимизация газа**: В некоторых случаях использование предварительно вычисленных констант может снизить расход газа.

## Рекомендации по расширению

При добавлении новых модулей или сервисов следует добавлять соответствующие константы в `CoreDefs`, следуя установленным соглашениям об именовании:

- `MODULE_ID` суффикс для идентификаторов модулей
- `SERVICE_` префикс для идентификаторов сервисов
- `ALIAS_` префикс для строковых алиасов

Это обеспечит согласованность и понятность кода при расширении системы.
