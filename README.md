# evmcontest
[![Coverage](https://img.shields.io/badge/coverage-90%25-brightgreen)](https://github.com/vitekes/evmcontest/actions/workflows/ci.yml)

**A platform for organizing prize contests on EVM networks**

## What is evmcontest?

**evmcontest** is a suite of smart contracts and utilities designed for rapid and secure integration of contest mechanics into any Ethereum Virtual Machine (EVM)–based decentralized project.

### Why use it?

- **Development speed**: Get a ready-made contest factory and escrow contracts instead of rolling your own logic.
- **Security**: Auditable modular contracts based on best practices.
- **Flexibility**: Configurable prize distribution templates, support for ERC-20 and ETH, extendable for NFTs and other assets.

### Use cases

- Organizing bounty programs
- Hosting tournaments and competitions with prize pools
- Decentralized auctions and gamification
- Any scenario requiring guaranteed custody and distribution of prizes

## Key features

- **ContestFactory** — create and manage contests
- **ContestEscrow** — isolated escrow for prize funds and winner distribution
- **NetworkFeeManager** — configure and collect platform fees
- **TokenValidator** — allowlist/blocklist ERC-20 tokens
- **PrizeTemplates** & **PrizeManager** — built-in distribution templates and NFT prize support
- **CreatorBadges** — award badges to contest organizers

## Quick Start

1. Ensure you are using **Node.js 20** (for example via `nvm use 20`) and install dependencies (including Hardhat and `@nomicfoundation/hardhat-toolbox`):

   ```bash
   git clone https://github.com/vitekes/evmcontest.git
   cd evmcontest
   npm install
   ```
   > The `lib` directory stores external libraries. Only `lib/chainlink` is tracked in Git; other subfolders may be ignored.
2. Create a `.env` file:

   ```env
   PRIVATE_KEY=your_private_key
   RPC_URL=https://...
   ```
3. Launch a local network and deploy:
   ```bash
   npx hardhat node
   npm run deploy:local
   ```
4. Run tests:
   ```bash
   npm test
   ```
   (Do not use `npx test` — it installs an unrelated package.)

5. Run the showcase script to see a complete end-to-end flow:
This script deploys all demo contracts, registers modules and performs a marketplace sale in multiple currencies.
   ```bash
   npx hardhat run scripts/showcase-marketplace.ts --network localhost
   ```

## Deployment order
# Blockchain Payment and Governance System

Система для управления платежами и доступом в блокчейн-проектах с интеграцией различных модулей.

### Упрощенный процесс деплоя системы

В проекте используется улучшенная архитектура с объединенным контрактом `CoreSystem`, который решает проблему циклической зависимости между компонентами. Вы можете использовать скрипт `deploy-core.ts` для автоматизированного деплоя:

```bash
npx hardhat run scripts/deploy/deploy-core.ts --network localhost
```

Или использовать полный демонстрационный скрипт, который разворачивает все компоненты системы:

```bash
npx hardhat run scripts/demos/deploy-showcase-full.ts --network localhost
```

## Архитектура ядра

Ядро системы состоит из следующих компонентов:

- **CoreSystem** - объединенная система управления доступом и регистрации компонентов
- **FeeManager** - менеджер комиссий для транзакций
- **PaymentGateway** - шлюз для обработки платежей
- **TokenValidator** - валидатор токенов для платежей

## Начало работы

### Установка зависимостей

```bash
npm install
```

### Компиляция контрактов

```bash
npx hardhat compile
```

### Запуск тестов

```bash
npx hardhat test
```

### Деплой ядра системы

```bash
npx hardhat run --network localhost scripts/deploy/deploy-core.ts
```

## Демо-скрипты

Проект содержит демонстрационные скрипты в каталоге `scripts/demo`:

```bash
# Отчет по расходу газа
npx hardhat run --network localhost scripts/demo/gas-report-demo.ts
```

## Документация
# Платежная система на смарт-контрактах

## Описание архитектуры

Платежная система представляет собой модульную архитектуру, основанную на интерфейсах с четкой иерархией и разделением ответственности.

### Ключевые компоненты

#### Интерфейсы

- **IPaymentComponent** - базовый интерфейс для всех компонентов системы
- **IPaymentProcessor** - интерфейс для обработчиков платежей
- **IPaymentGateway** - интерфейс для платежных шлюзов
- **IPaymentFactory** - интерфейс для фабрик компонентов
- **IProcessorRegistry** - интерфейс для реестра процессоров

#### Реализации

- **PaymentGateway** - основная реализация платежного шлюза
- **PaymentGatewayFactory** - фабрика для создания экземпляров шлюзов
- **ProcessorRegistry** - реестр процессоров платежей
- **BaseProcessor** - базовая реализация для процессоров
- **FeeProcessor** - процессор для работы с комиссиями

## Взаимодействие компонентов

1. **Создание платежного шлюза**:
   - `PaymentGatewayFactory` создает экземпляр `PaymentGateway` для конкретного модуля
   - Конфигурация шлюза хранится в фабрике

2. **Обработка платежей**:
   - `PaymentGateway` получает запрос на обработку платежа
   - Создается контекст платежа с помощью `PaymentContextLibrary`
   - Контекст последовательно обрабатывается цепочкой процессоров
   - Каждый процессор может модифицировать контекст или отклонить платеж

3. **Управление ролями**:
   - Каждый контракт использует стандартный `AccessControl` для назначения ролей
   - Роли могут быть как для процессоров, так и для администраторов системы

## Пример использования

```solidity
// Пример обработки платежа через шлюз
function processPayment(address token, uint256 amount) external {
    bytes32 moduleId = keccak256("MY_MODULE");
    IGateway gateway = IGateway(gatewayAddress);

    // Обработка платежа через шлюз
    uint256 netAmount = gateway.processPayment(
        moduleId,
        token,
        msg.sender,
        amount,
        ""
    );

    // Дальнейшая логика обработки платежа
}
```
Полная документация доступна в каталоге `docs/`.
The Ignition modules deploy contracts in the following sequence:

1. **CoreModule** – deploys `CoreSystem`, `FeeManager`,
   `PaymentGateway`, `TokenValidator`, `MarketplaceFactory` and a `ChainlinkPriceOracle` (or `MockPriceFeed` for testing).
   The marketplace module is registered along with validator and gateway services.
2. **LocalDeploy** – in addition to the core contracts it deploys a test ERC-20
   token and the contest module (`ContestFactory` with its validator) for local
   development.
3. **PublicDeploy** – similar to `LocalDeploy` but omits the test token and is
   intended for testnets or mainnet.

Use the provided npm scripts to deploy:

```bash
npm run deploy:local     # local Hardhat network
npm run deploy:sepolia   # Sepolia testnet
npm run deploy:mainnet   # Ethereum mainnet
```

## Как запустить Foundry

1. Установите инструментарий Foundry:
   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   ```
2. Запустите тесты:
   ```bash
   forge test
   ```

## Documentation

For detailed information, see:

- **Architecture**: `docs/architecture.md`
- **API**: `docs/api/`
- **Examples**: `docs/examples.md`
- **Testing**: `docs/testing.md`
- **Migrations & Deployment**: `docs/migrations.md`
- **CHANGELOG**: `CHANGELOG.md`

## Deployment notes

After deploying the core `PaymentGateway` contract, make sure to register it in the `CoreSystem` for each module:

```solidity
coreSystem.setModuleServiceAlias(MODULE_ID, "PaymentGateway", gatewayAddress)
```

Without this step modules won't be able to discover the gateway service.

## Как добавить модуль

1. Создайте смарт‑контракты модуля и необходимые сервисы.
2. Задеплойте их в сеть и получите `moduleId`.
3. Зарегистрируйте модуль в `CoreSystem`:
   ```solidity
   coreSystem.registerFeature(moduleId, moduleAddress, 1);
   ```
4. Установите алиасы сервисов, например `PaymentGateway`:
   ```solidity
   coreSystem.setModuleServiceAlias(moduleId, "PaymentGateway", gatewayAddress);
   ```

```mermaid
graph TD
    A(Deploy contracts) --> B{Register in CoreSystem}
    B --> C[Set service aliases]
    C --> D[Module ready]
```

## Contributing & Support

- **GitHub Issues**: [https://github.com/vitekes/evmcontest/issues](https://github.com/vitekes/evmcontest/issues)
- Pull requests are welcome!

## License

MIT License. © 2025 evmcontest team


