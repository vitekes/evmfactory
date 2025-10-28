# Deployment Guide

## Prerequisites

- Node.js 20+
- npm
- Hardhat (bundled with the repo)

## Fast local deployment (demo)

Use the Ignition module against an in-process Hardhat network:

```bash
npm run deploy:demo
```

It relies on `ignition/parameters/dev.ts` and writes addresses to `demo/.deployment.json`.

## Custom deployments

Deploy Ignition modules directly (скрипт автоматически подбирает файл параметров по имени сети, например `ignition/parameters/sepolia.json`):

```bash
npx hardhat run scripts/deploy.ts --network <network>
```

Можно переопределить путь к параметрам через переменную окружения `DEPLOY_PARAMS=/path/to/params.json` (и `DEPLOY_ID` для идентификатора деплоя). При запуске скрипта напрямую через `node` остаются доступны флаги `--parameters` и `--deployment-id`.

### Parameters

- `DEFAULT_FEE_BPS` — базовая комиссия для `FeeProcessor`.
- `AUTOMATION_ACCOUNT` — EOA/сервис, который будет выполнять автоматизацию (используется по умолчанию).
- `contestAllowedTokens` / `subscriptionAllowedTokens` — списки разрешённых токенов для `TokenFilter`.
- `subscriptionMaxActivePlans` — лимит активных планов на автора (передаётся в `PlanManager`).
- `subscriptionAuthors` — массив адресов, которым Ignition сразу выдаст `AUTHOR_ROLE`.
- `subscriptionAutomation` — аккаунты, получающие `AUTOMATION_ROLE` для `charge`/`markFailedCharge`.

You can bypass auto-deployment by providing `.env.demo` with the following variables (used by `demo/config/addresses.ts`):

```
DEMO_CORE=0x...
DEMO_PAYMENT_GATEWAY=0x...
DEMO_PR_REGISTRY=0x...
DEMO_TOKEN_FILTER=0x...
DEMO_FEE_PROCESSOR=0x...
DEMO_CONTEST_FACTORY=0x...
DEMO_SUBSCRIPTION_MANAGER=0x...
DEMO_TEST_TOKEN=0x...
```

## Role configuration

- `ContestFactory.createContest` требует `FEATURE_OWNER_ROLE`. Выдайте роль всем менеджерам: `core.grantRole(FEATURE_OWNER_ROLE, <address>)`.
- Авторы тарифов получают `AUTHOR_ROLE` перед вызовами `PlanManager.createPlan`. Ignition может выдать роли через параметр `subscriptionAuthors`, дополнительные аккаунты выдаются вручную.
- Автоматизация (`charge`, `chargeBatch`, `markFailedCharge`) требует `AUTOMATION_ROLE`. Ignition использует `subscriptionAutomation`, сторонним сервисам роль выдаётся через `core.grantRole`.

## Native subscription deposits

- `SubscriptionManager` now exposes `depositNativeFunds`, `withdrawNativeFunds`, and `getNativeDeposit` for native-currency subscriptions.
- When subscribing with `plan.token == address(0)`, send at least `plan.price` via `msg.value`; any surplus is stored in the user's deposit and reused by `charge`/`chargeBatch`.
- Automation should monitor `nativeDeposits[user]` and replenish it before the next billing cycle to avoid `ChargeSkipped` with reason `SKIP_REASON_INSUFFICIENT_NATIVE_DEPOSIT`.

## PlanManager & billing automation

- Каждый тариф должен быть зарегистрирован через `PlanManager.createPlan` (Ignition деплоит его автоматически и формирует сервис `PlanManager` в CoreSystem).
- Для ручного или миграционного добавления планов используйте те же EIP-712 данные, что подписываются мерчантом для `SubscriptionManager`.
- Off-chain биллинг (ретраи/регулярные списания) запускается через `scripts/run-billing-worker.ts`. Базовый пример конфигурации: `scripts/billing-config.example.json`.  
  ```bash
  npm run billing:worker -- --network <network> --config scripts/billing-config.json
  ```
- Дополнительные рекомендации по автоматизации изложены в `docs/subscription-billing-guide.md`.

## Миграция со старой модели

1. **Деплой**: обновите контракт `SubscriptionManager` и задеплойте `PlanManager` (Ignition делает это автоматически).
2. **Регистрация планов**: для каждого существующего `planHash` вызовите `PlanManager.createPlan` с оригинальной EIP-712 подписью мерчанта (понадобится скрипт миграции).
3. **Перенос подписок**: прочитайте состояние старого `subscribers[user]` и вызовите от оператора `SubscriptionManager.activateManually(user, planHash, ActivationMode.StartNextPeriod)`, чтобы восстановить активные планы без мгновенного списания. При необходимости скорректируйте `nextChargeAt`/`retryAt` заранее (через подготовку storage перед апгрейдом либо отдельный скрипт), чтобы сохранить график списаний.
4. **Проверка**: запустите `npm run billing:worker` в dry-run режиме и убедитесь, что подписки успешно обрабатываются.

## CI / smoke-checks

1. `npm run lint` (or `npm run lint:fix`) — Prettier formatting for Solidity.
2. `npx hardhat test` — full unit/integration suite (включая PlanManager и ретраи).
3. `npm run demo:payment`, `npm run demo:subscription`, `npm run demo:contest` — end-to-end flows на локальной сети. Для `demo:contest` убедитесь, что вызывающий имеет `FEATURE_OWNER_ROLE`.
4. `npm run billing:worker -- --network hardhat --config scripts/billing-config.example.json` — быстрая проверка воркера списаний.

## Production notes

- Fill `ignition/parameters/prod.ts` with real addresses (automation, fee basis points, token allowlists).
- Keep secrets in CI vaults; set environment variables instead of committing `.env.demo`.
- Review processor chains after deployment with `PaymentOrchestrator.configureProcessor` calls.
- Document deployed addresses for operations and monitoring.
