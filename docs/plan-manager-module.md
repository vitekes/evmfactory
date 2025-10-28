# PlanManager: модуль управления тарифными планами

## Цели и границы
- Позволить авторам создавать и сопровождать несколько тарифных планов («tiers») в рамках «крипто-патреона».
- Обеспечить контроль доступа через ACL (`AUTHOR_ROLE`, `FEATURE_OWNER_ROLE`, `OPERATOR_ROLE`), не затрагивая остальные модули CoreSystem (Marketplace, Contest).
- Предоставить `SubscriptionManager` надёжный источник данных о планах для проверки активного статуса и параметров при подписке/ретраях.
- Синхронизировать off-chain и on-chain состояние через события; поддерживать обратную совместимость с существующими EIP-712 подписями мерчантов.

## Ответственность модуля
- Хранение метаданных планов (`price`, `period`, `token`, `status`, `uri`, `merchant`).
- Контроль статуса плана (`Active`/`Inactive`) и уведомление подписочного модуля о деактивациях.
- Учет версии плана: любое изменение цены/периода требует нового `planHash`.
- Обеспечение индекса по автору (пагинация активных и исторических планов).
- Инструменты для операторов (заморозка планов, передача владельца при необходимости).

## Модель данных

### Структура `Plan`
| Поле            | Тип      | Описание                                                        |
|-----------------|----------|-----------------------------------------------------------------|
| `bytes32 hash`  | bytes32  | EIP-712 hash плана (`SignatureLib.hashPlan`).                   |
| `address merchant` | address | Автор/мерчант, владевший планом на момент создания.            |
| `uint128 price` | uint128  | Стоимость одного биллингового периода.                          |
| `uint32 period` | uint32   | Период в секундах (ожидается 2592000 = 30 дней).                |
| `address token` | address  | Адрес токена (0 для native).                                    |
| `Status status` | enum     | `Inactive` (0), `Active` (1), `Frozen` (2).                     |
| `uint48 createdAt` | uint48| Timestamp создания.                                             |
| `uint48 updatedAt` | uint48| Timestamp последнего изменения статуса.                         |
| `string uri`    | string   | Off-chain описание (IPFS/HTTPS).                                |

Статус `Frozen` используется операторами для временной блокировки (например, при расследовании).

### Индексы
- `plans[planHash] -> PlanData`.
- `merchantPlanHistory[merchant] -> bytes32[]` — история всех созданных планов мерчанта.
- `activePlans[merchant] -> bytes32[]` — список активных `planHash`, который использует SubscriptionManager и фронтенд.
- `activePlanIndexes[merchant][planHash] -> uint256` — индекс в `activePlans` (index + 1) для O(1) удаления).



## ACL и роли
- `AUTHOR_ROLE` — право создавать планы и менять `uri`. Назначается через CoreSystem администраторами.
- `FEATURE_OWNER_ROLE` — развёртывание/конфигурация модуля, может обновлять сервисные параметры.
- `OPERATOR_ROLE` — служба поддержки: может деактивировать/заморозить план, сменить владельца.
- `GOVERNOR_ROLE` — настройка глобальных лимитов (макс. число планов на автора).

## Жизненный цикл плана
1. **Создание (`createPlan`)**
   - Автор предоставляет EIP-712 план (`SignatureLib.Plan`) и подпись мерчанта.
   - `planHash` вычисляется on-chain; проверяется, что план ещё не зарегистрирован.
   - Проверяется лимит активных планов на автора (`maxActivePlans`).
   - План сохраняется со статусом `Active`, добавляется в `activePlans` и историю `merchantPlanHistory`.
   - Эмитируются `PlanCreated` и `PlanStatusChanged(..., PlanStatus.Active)`.

2. **Обновление метаданных (`updatePlanUri`)**
   - Автор может обновить `uri` без изменения цены/периода (не влияет на подпись).

3. **Деактивация (`deactivatePlan`)**
   - Автор или оператор переводит план в статус `Inactive`.
   - Удаляется из `activePlans`.
   - Эмитируется `PlanStatusChanged`.
   - Отправляется уведомление `SubscriptionManager` (через событие или прямой вызов) об изменении статуса.

4. **Активация (`activatePlan`)**
   - Доступно только если план был деактивирован автором/оператором и подпись всё ещё валидна.
   - Проверяется, что активных планов не превышено.
   - Восстанавливается в `activePlans`.

5. **Заморозка (`freezePlan`)**
   - Только операторы. Статус `Frozen`; пользователь не может подписаться на такой план.
   - Используется при расследовании злоупотреблений. Эмитируются PlanFrozenToggled и PlanStatusChanged.

6. **Переиздание**
   - Изменение цены/периода требует нового EIP-712 плана и `createPlan`; старый должен быть переведён в `Inactive`.

## Основные функции

```solidity
interface IPlanManager {
    function createPlan(
        SignatureLib.Plan calldata plan,
        bytes calldata sigMerchant,
        string calldata uri
    ) external;

    function deactivatePlan(bytes32 planHash) external;

    function activatePlan(bytes32 planHash) external;

    function freezePlan(bytes32 planHash, bool frozen) external;

    function updatePlanUri(bytes32 planHash, string calldata uri) external;

    function transferPlanOwnership(bytes32 planHash, address newMerchant) external;

    function setMaxActivePlans(uint8 newLimit) external;
}
```

- `createPlan`/`activatePlan` проверяют наличие `AUTHOR_ROLE` у msg.sender и соответствие `plan.merchant == msg.sender`.
- `transferPlanOwnership` используется в форс-мажорах: обновляет `merchant`, переносит запись в индексах.
- `freezePlan(planHash, true)` устанавливает `status = Frozen`, снимает в `activePlans`.

## View-хелперы
- getPlan(bytes32 planHash) returns (PlanData memory)
- listMerchantPlans(address merchant) returns (bytes32[] memory)
- listActivePlans(address merchant) returns (bytes32[] memory)
- isPlanActive(bytes32 planHash) returns (bool)
- planStatus(bytes32 planHash) returns (PlanStatus)

Дополнительно для фронтенда можно добавить `getPlanInfo` с раскрытием цены/периода.

## События
- PlanCreated(address indexed merchant, bytes32 indexed planHash, uint256 price, address token, uint32 period, string uri)
- PlanStatusChanged(address indexed merchant, bytes32 indexed planHash, PlanStatus status)
- PlanFrozenToggled(address indexed operator, bytes32 indexed planHash, bool frozen)
- `PlanUriUpdated(address indexed merchant, bytes32 indexed planHash, string uri)`
- `PlanOwnershipTransferred(address indexed operator, bytes32 indexed planHash, address oldMerchant, address newMerchant)`
- `MaxActivePlansUpdated(uint8 oldLimit, uint8 newLimit)`

`PlanStatus` кодируется как: `0=Inactive`, `1=Active`, `2=Frozen`.

## Интеграция с SubscriptionManager
- При `createPlan`/`activatePlan` SubscriptionManager может подписаться на события, чтобы актуализировать кеш `planSnapshots`.
- При `deactivatePlan`/`freezePlan` подписочный модуль должен блокировать новые подписки и, опционально, инициировать отмену у активных пользователей (обработка через off-chain).
- `SubscriptionManager` вызывает view-функции `isPlanActive`, `getPlan` при подписке и ретрае.
- Для миграции: при развертывании PlanManager загружается список существующих `plans[planHash]` из старого контракта (если требуется) скриптом и синхронизируется off-chain.

## Ошибки
- `PlanAlreadyExists()`
- `PlanNotFound()`
- PlanInactive()
- `PlanFrozen()`
- `UnauthorizedMerchant()`
- `ActivePlanLimitReached()`
- `InvalidSignature()` (если `sigMerchant` некорректна)
- `Forbidden()` для отсутствия роли

## Ограничения и оптимизация
- Хранение цены в `uint128` достаточно для токенов с 18 знаками; экономим слот, упаковывая `period` и `status` в один `uint256`.
- Максимум планов на автора ограничивается `uint8` (0 означает неограниченно).
- `listActivePlans` не должен возвращать более 32 элементов без пагинации, чтобы экономить газ — используем массив `bytes32[]` плюс off-chain выборку.

## Тестовый контур
- Создание плана с корректной подписью → `PlanCreated`, статус `Active`.
- Повторное создание того же `planHash` → revert `PlanAlreadyExists`.
- Превышение лимита активных планов → revert.
- Деактивация и повторная активация → проверка индексов и событий.
- Заморозка и попытка активaции/подписки → PlanFrozen()().
- Обновление URI без влияния на подпись.
- Передача владельца и проверка, что только новый merchant может обновлять план.

## Миграция
- При первой установке модуль пуст, лимит активных планов задаётся `setMaxActivePlans`.
- Для существующих планов: off-chain скрипт формирует транзакции `createPlan` с исходными хешами и статусами (можно использовать `FEATURE_OWNER_ROLE` для массовой загрузки).
- После миграции SubscriptionManager начинает читать статусы только из PlanManager.

