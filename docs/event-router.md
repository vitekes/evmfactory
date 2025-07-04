# Система маршрутизации событий (EventRouter)

## Обзор

EventRouter — это централизованный механизм для маршрутизации событий в системе. Он позволяет модулям генерировать типизированные события, которые могут отслеживаться и обрабатываться внешними системами и сервисами.

## Архитектура

EventRouter реализует шаблон "издатель-подписчик" (publisher-subscriber) для смарт-контрактов:

1. **Модули** (издатели) генерируют события через метод `route()`
2. **Внешние системы** (подписчики) отслеживают событие `EventRouted`
3. **Registry** управляет доступом к EventRouter через систему сервисов

## Поддерживаемые типы событий

```solidity
enum EventKind {
    Unknown,            // Неизвестный тип (запрещен)
    ListingCreated,     // Создание листинга в маркетплейсе
    SubscriptionCharged,// Оплата подписки
    ContestFinalized,   // Финализация конкурса
    PaymentProcessed,   // Обработка платежа через PaymentGateway
    TokenConverted,     // Конвертация токенов
    SubscriptionCreated,// Создание новой подписки
    MarketplaceSale,    // Продажа NFT в маркетплейсе
    UserRegistered      // Регистрация нового пользователя
}
```

## Интеграция в модули

Чтобы интегрировать EventRouter в модуль, следуйте этому шаблону:

```solidity
// Получение EventRouter из Registry
address router = registry.getModuleService(MODULE_ID, CoreDefs.SERVICE_EVENT_ROUTER);
if (router != address(0)) {
    // Подготовка данных события (можно использовать любую структуру, закодированную в bytes)
    bytes memory payload = abi.encode(param1, param2, param3);
    // Отправка события
    EventRouter(router).route(EventRouter.EventKind.YourEventType, payload);
}
```

## Прослушивание событий

События можно прослушивать с помощью стандартных механизмов Ethereum:

```javascript
// JavaScript (ethers.js)
const eventRouterContract = new ethers.Contract(routerAddress, routerAbi, provider);

// Прослушивание всех событий
eventRouterContract.on('EventRouted', (kind, payload, event) => {
  console.log(`Получено событие типа: ${kind}`);
  // Декодирование payload в зависимости от типа события
  if (kind === 1) { // ListingCreated
    const decodedData = ethers.utils.defaultAbiCoder.decode(['address', 'uint256'], payload);
    console.log('Листинг создан:', decodedData);
  }
});

// Прослушивание конкретного типа события
eventRouterContract.on(eventRouterContract.filters.EventRouted(3), (kind, payload, event) => {
  console.log('Конкурс финализирован!');
  const [creator, winners, prizes] = ethers.utils.defaultAbiCoder.decode(
    ['address', 'address[]', 'tuple(uint8,address,uint256,string,uint8)[]'], 
    payload
  );
});
```

## Преимущества использования EventRouter

1. **Централизация событий**: Все важные события системы доступны через единый интерфейс.

2. **Гибкость**: Можно добавлять новые типы событий без изменения существующих контрактов.

3. **Контроль доступа**: Только авторизованные модули могут генерировать события.

4. **Масштабируемость**: Внешние системы могут подписываться только на интересующие их типы событий.

## Примеры использования

### Маркетплейс

При создании нового листинга:

```solidity
EventRouter(router).route(
  EventRouter.EventKind.ListingCreated, 
  abi.encode(seller, tokenId, price, metadata)
);
```

### Подписки

При успешном списании средств по подписке:

```solidity
EventRouter(router).route(
  EventRouter.EventKind.SubscriptionCharged, 
  abi.encode(subscriber, merchant, amount, nextBillingDate)
);
```

### Конкурсы

При финализации конкурса и выплате призов:

```solidity
EventRouter(router).route(
  EventRouter.EventKind.ContestFinalized, 
  abi.encode(creator, winners, prizes)
);
```

## Формат данных для каждого типа события

В этом разделе описаны параметры, которые кодируются в `payload` для каждого типа события.

### ListingCreated
```solidity
abi.encode(
    uint256 listingId,     // ID листинга
    address seller,        // Продавец
    address tokenContract, // Адрес контракта токена
    uint256 tokenId,       // ID токена
    uint256 price,         // Цена
    address currency,      // Валюта
    uint256 expiresAt,     // Срок действия
    bytes metadata         // Метаданные
)
```

### SubscriptionCharged
```solidity
abi.encode(
    address subscriber,    // Подписчик
    address merchant,      // Продавец
    bytes32 planHash,      // Хеш плана
    address token,         // Токен оплаты
    uint256 amount,        // Сумма платежа
    uint256 nextBillingTime// Следующее списание
)
```

### ContestFinalized
```solidity
abi.encode(
    address creator,       // Создатель конкурса
    address[] winners,     // Список победителей
    PrizeInfo[] prizes     // Информация о призах
)
```

### PaymentProcessed
```solidity
abi.encode(
    bytes32 moduleId,     // Идентификатор модуля
    address payer,         // Плательщик
    address token,         // Токен платежа
    uint256 amount,        // Полная сумма
    uint256 netAmount,     // Чистая сумма после комиссии
    uint256 commissionAmount, // Сумма комиссии
    string referenceCode   // Код ссылки/основание платежа
)
```

### TokenConverted
```solidity
abi.encode(
    bytes32 moduleId,     // Идентификатор модуля
    address fromToken,     // Исходный токен
    address toToken,       // Целевой токен
    uint256 amount,        // Исходная сумма
    uint256 result         // Конвертированная сумма
)
```

### SubscriptionCreated
```solidity
abi.encode(
    address subscriber,    // Подписчик
    address merchant,      // Продавец
    bytes32 planHash,      // Хеш плана
    address paymentToken,  // Токен оплаты
    uint256 paymentAmount, // Сумма платежа
    uint256 period,        // Период подписки
    uint256 nextBillingTime// Следующее списание
)
```

### MarketplaceSale
```solidity
abi.encode(
    uint256 listingId,     // ID листинга
    address seller,        // Продавец
    address buyer,         // Покупатель
    address tokenContract, // Адрес контракта токена
    uint256 tokenId,       // ID токена
    uint256 price,         // Цена
    address currency,      // Валюта
    uint256 timestamp      // Время продажи
)
```

### UserRegistered
```solidity
abi.encode(
    address user,          // Адрес пользователя
    uint256 timestamp,     // Время регистрации
    bytes metadata         // Дополнительные данные о пользователе
)
```

## Расширение системы

Для добавления нового типа события:

1. Добавьте новое значение в перечисление `EventKind`
2. Обновите документацию с описанием формата payload для нового типа
3. Интегрируйте вызов `route()` в соответствующие модули

## Тестирование

Для тестирования можно использовать `MockEventRouter.sol`, который имеет тот же интерфейс, но не выполняет никаких действий.
