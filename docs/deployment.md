# Deployment Guide

## Prerequisites

- Node.js 20+
- npm
- Hardhat (bundled with repo)
- (optional) Foundry if you run the full CI pipeline

## Fast local deployment (demo)

This runs Ignition against the in-process Hardhat network and prints deployed addresses:

`ash
npm run deploy:demo
`

It uses ignition/parameters/dev.ts.

## Custom deployments

Use Ignition directly:

`ash
npx hardhat ignition deploy ignition/modules/deploy.ts \
  --network <network> \
  --parameters ignition/parameters/<env>.ts
`

Parameters available:

- DEFAULT_FEE_BPS – default commission for FeeProcessor
- AUTOMATION_ACCOUNT – address allowed to trigger automated tasks
- contestAllowedTokens / subscriptionAllowedTokens – configure TokenFilter per module

Override addresses (skip auto-deploy) by providing .env.demo:

`
DEMO_CORE=0x...
DEMO_PAYMENT_GATEWAY=0x...
DEMO_PR_REGISTRY=0x...
DEMO_TOKEN_FILTER=0x...
DEMO_FEE_PROCESSOR=0x...
DEMO_CONTEST_FACTORY=0x...
DEMO_SUBSCRIPTION_MANAGER=0x...
DEMO_TEST_TOKEN=0x...
`

## CI / Smoke tests

GitHub Actions workflow (.github/workflows/ci.yml) runs:

1. Forge + Hardhat tests
2. 
pm run demo:payment
3. 
pm run demo:subscription
4. 
pm run demo:contest

This ensures Ignition deploys and baseline flows execute.

## Production notes

- Fill ignition/parameters/prod.ts with real addresses (automation, fee basis points, token lists).
- Keep secrets in CI vault; set environment variables instead of committing .env.demo.
- Review processor configuration after deployment using PaymentOrchestrator.configureProcessor scripts.

