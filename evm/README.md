# EVM Factory (EVM project)

This directory hosts the Hardhat implementation. Run all npm commands from `evm/`.

# EVM Factory

EVM Factory provides a modular payment stack for Hardhat-based projects. It includes a Payment Gateway with processor orchestration, a Subscription Manager that supports ERC-20 and native cycles, and a Contest Factory for prize escrow flows. The repository ships demo scenarios, deployment modules, and end-to-end tests covering the main integrations.

## Features

- PaymentGateway orchestrated by PaymentOrchestrator and ProcessorRegistry with plug-in processors (discount, fee, token filter).
- SubscriptionManager v2 with multi-plan storage `(user, planHash)`, retry scheduling, native deposits, and automation hooks.
- PlanManager providing ACL-guarded plan CRUD and max active plan limits per merchant.
- ContestFactory + ContestEscrow for prize distribution backed by CoreSystem services.
- Ignition deployment modules for demo, local, and production networks.
- Demo scenarios (`npm run demo:*`) showcasing payment, subscription, and contest flows.

## Requirements

- Node.js 20+
- npm
- Hardhat (bundled in `devDependencies`)

Install dependencies once:

```
npm install
```

## Useful Scripts

- `npm run compile` – Hardhat compile.
- `npm run test` – Hardhat unit/integration tests.
- `npm run lint` – Prettier check for Solidity contracts.
- `npm run demo:payment` – Runs the payment scenario against Hardhat network.
- `npm run demo:subscription` – Updated subscription scenario (PlanManager + retry billing).
- `npm run demo:contest` – Runs the contest scenario.
- `npm run demo:marketplace` – Runs the marketplace scenario (off-chain listing purchase).
- `npm run billing:worker` – Executes the billing worker (`scripts/run-billing-worker.ts`).

See `package.json` for the full script list. Demo scripts rely on Ignition deployment helpers located in `ignition/modules/*`.

## Native Subscription Flow

Native currency subscriptions require prefunding:

1. Call `SubscriptionManager.depositNativeFunds` to top up a user balance (or send extra `msg.value` during `subscribe`).
2. `subscribe` or `subscribeWithToken` with `plan.token == address(0)` must include `msg.value >= plan.price` for the first cycle; any excess is stored in the user deposit.
3. Automation can call `charge`/`chargeBatch`; the contract debits `nativeDeposits[user]` and forwards net proceeds via PaymentGateway.
4. Users can withdraw unused funds with `withdrawNativeFunds` or automatically receive them during `unsubscribe`.

## Testing

```
npx hardhat test
```

CI also executes demo scenarios through `.github/workflows/ci.yml`. When modifying processors or Ignition modules, update `docs/deployment.md` if new parameters are required.

## Documentation

- Deployment notes: `docs/deployment.md`
- Hardhat demos: `demo/scenarios/*`
- Billing automation: `docs/subscription-billing-guide.md`
- Tests: `test/modules`, `test/payments`, `test/integration`

Feel free to open issues or PRs to expand processor coverage, add new modules, or improve the documentation.
