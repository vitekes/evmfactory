# Автоматизация биллинга мультиподписок

## Цели
- Настроить оффчейн-воркеры, которые инициируют регулярные списания через `SubscriptionManager`.
- Обрабатывать неудачные попытки: ставить повтор после первой ошибки и деактивировать подписку после второй.
- Обеспечить наблюдаемость и защиту от повторных запуска.

## Компоненты
- **SubscriptionManager** (on-chain): функции `charge(address,bytes32)` и `markFailedCharge(address,bytes32)` доступны аккаунтам с ролью `AUTOMATION_ROLE`.
- **PlanManager**: предоставляет статус плана и гарантирует, что нельзя списывать по заблокированному плану.
- **Billing worker (`scripts/run-billing-worker.ts`)**: утилита на Hardhat/TypeScript, выполняющая батч зарядов.
- **Конфигурация воркера (`scripts/billing-config.json`)**: список адресов пользователей для проверки и адрес контракта.

## Поток воркера
1. Читает конфиг (по умолчанию `scripts/billing-config.json`).
2. Для каждого пользователя:
   - Получает перечень планов `listUserPlans`.
   - Берёт активный план (статус `Active`).
   - Сравнивает `nextChargeAt`/`retryAt` с текущим временем.
3. Если подписка просрочена:
   - Пытается выполнить `charge(address,bytes32)`.
   - При успехе — логирует `charged`.
   - При ошибках `InsufficientBalance`, `PlanInactive`, `PlanNotFound` — вызывает `markFailedCharge` для постановки ретрая/деактивации.
   - Для `NotDue` и других причин — помечает подписку как `skipped`.
4. Выводит таблицу результатов, пригодную для мониторинга.

## Роли и права
- Аккаунт, который запускает воркер, обязан иметь `AUTOMATION_ROLE`. Для локальной разработки можно выдать роль через `npx hardhat console`:
  ```ts
  const core = await ethers.getContractAt('CoreSystem', CORE_ADDRESS);
  await core.grantRole(await core.AUTOMATION_ROLE(), AUTOMATION_ACCOUNT);
  ```
- Авторы планов получают `AUTHOR_ROLE` (deploy/скриптом или вручную) до вызова `PlanManager.createPlan`.

## Использование утилиты
```bash
npm install
npx hardhat run scripts/run-billing-worker.ts --network <network> --config path/to/billing-config.json
```

Параметр `--config` (необязателен) указывает путь к JSON-конфигу. Структура примера: `scripts/billing-config.example.json`.

## Рекомендации для продакшена
- Запускать воркер по расписанию (cron/k8s job) чаще, чем биллинг-период (например, раз в час).
- Логировать результаты (stdout → ELK, Cloud Logging).
- Снимать метрики успешных/неудачных списаний и ретраев.
- Добавить алертинг на рост `retry-scheduled`/`skipped` с причинами `plan-inactive`.
- Хранить список пользователей для обработки в индексе (off-chain база), добавляя адрес при `SubscriptionActivated` и удаляя при `SubscriptionCancelled`/`SubscriptionFailedFinal`.

## Интеграционные шаги
1. **Миграция**: при обновлении на мультиподписки сверить требования (`docs/subscription-multi-tier-plan.md`) и архитектуру (`docs/subscription-multi-tier-architecture.md`), затем заполнить `PlanManager` и перенести активные подписки.
2. **Деплой**: в Ignition добавлены сервисы:
   - `PlanManager` автоматически разворачивается и регистрируется.
   - Параметры `subscriptionAuthors`, `subscriptionAutomation`, `subscriptionMaxActivePlans` доступны через Ignition.
3. **Demo-сценарий**: `npm run demo:subscription` (или прямой запуск `demo/scenarios/run-subscription-scenario.ts`) проверяет:
   - Регистрацию плана в `PlanManager`.
   - Подписку и повторное списание с помощью `charge(address,bytes32)`.

## Проверка
- `npm test` — on-chain тесты покрывают ретраи, переключение планов, роли оператора.
- `npx hardhat run demo/scenarios/run-subscription-scenario.ts` — smoke-тест оффчейн сценария.
- `npx hardhat run scripts/run-billing-worker.ts --config scripts/billing-config.example.json` (с корректными адресами) — проверка воркера.
