# Deployment Guide

## Prerequisites

- Node.js 20+
- npm
- Hardhat (bundled with the repo)
- (optional) Foundry if you run the full CI pipeline

## Fast local deployment (demo)

Use the Ignition module against an in-process Hardhat network:

```bash
npm run deploy:demo
```

It relies on `ignition/parameters/dev.ts` and writes addresses to `demo/.deployment.json`.

## Custom deployments

Deploy Ignition modules directly:

```bash
npx hardhat ignition deploy ignition/modules/deploy.ts \
  --network <network> \
  --parameters ignition/parameters/<env>.ts
```

### Parameters

- `DEFAULT_FEE_BPS` � default commission for `FeeProcessor`.
- `AUTOMATION_ACCOUNT` � address allowed to trigger scheduled tasks.
- `contestAllowedTokens` / `subscriptionAllowedTokens` � token allowlists for `TokenFilter`.

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

- `ContestFactory.createContest` requires the caller to hold `FEATURE_OWNER_ROLE` in `CoreSystem`. Grant the role once per manager account: `core.grantRole(FEATURE_OWNER_ROLE, <address>)`.
- Automation EOAs (for `charge`/`chargeBatch`) must also receive the corresponding role (`AUTOMATION_ROLE`). Ignition assigns roles to on-chain services, but any extra EOA must be added manually.

## Native subscription deposits

- `SubscriptionManager` now exposes `depositNativeFunds`, `withdrawNativeFunds`, and `getNativeDeposit` for native-currency subscriptions.
- When subscribing with `plan.token == address(0)`, send at least `plan.price` via `msg.value`; any surplus is stored in the user's deposit and reused by `charge`/`chargeBatch`.
- Automation should monitor `nativeDeposits[user]` and replenish it before the next billing cycle to avoid `ChargeSkipped` with reason `SKIP_REASON_INSUFFICIENT_NATIVE_DEPOSIT`.

## CI / smoke-checks

1. `npm run lint` (or `npm run lint:fix`) � Prettier formatting for Solidity.
2. `npx hardhat test` � full unit/integration suite, including native-deposit coverage.
3. `npm run demo:payment`, `npm run demo:subscription`, `npm run demo:contest` � end-to-end flows on Hardhat. For `demo:contest` make sure the caller has `FEATURE_OWNER_ROLE` as described above.

## Production notes

- Fill `ignition/parameters/prod.ts` with real addresses (automation, fee basis points, token allowlists).
- Keep secrets in CI vaults; set environment variables instead of committing `.env.demo`.
- Review processor chains after deployment with `PaymentOrchestrator.configureProcessor` calls.
- Document deployed addresses for operations and monitoring.
