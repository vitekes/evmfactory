# Demo Scenarios

Скрипты демонстрируют платежи, подписки и конкурсы. Если адреса не заданы, Ignition автоматически развернёт стек (core + payment + модули) и сохранит их в demo/.deployment.json.

## Подготовка

1. (Опционально) используйте готовый набор параметров:
   `ash
   npx hardhat ignition deploy ignition/modules/deploy.ts --network hardhat --parameters ignition/parameters/dev.ts
   `
2. Для фиксации адресов зафиксируйте их в .env.demo (или отредактируйте cache-файл):
   `env
   DEMO_CORE=0x...
   DEMO_PAYMENT_GATEWAY=0x...
   DEMO_PR_REGISTRY=0x...
   DEMO_CONTEST_FACTORY=0x...
   DEMO_SUBSCRIPTION_MANAGER=0x...
   DEMO_TEST_TOKEN=0x...
   `

## Быстрый старт

`ash
npm run demo:payment
npm run demo:subscription
npm run demo:contest
`

Каждый сценарий:
- при необходимости разворачивает TestToken и базовые зависимости;
- логирует ключевые шаги ([INFO], [OK], [WARN]);
- завершает исполнение при первом сбое.

## Структура

`
demo/
  README.md
  .env.example
  config/
    addresses.ts
  utils/
    logging.ts
    signers.ts
    tokens.ts
    gateway.ts
    core.ts
  scenarios/
    run-payment-scenario.ts
    run-subscription-scenario.ts
    run-contest-scenario.ts
`

ignition/parameters/ содержит заготовки для dev/prod деплоя (параметры можно переопределять флагом --parameters).

