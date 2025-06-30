# Migrations

Contract deployment is handled via Hardhat Ignition modules. The main sequence is defined in `ignition/modules/CoreModule.ts` with additional setups for local and public networks.

## Deploy locally

```
npm run deploy:local
```

This deploys core contracts plus example modules on a Hardhat node.

## Deploy to a testnet or mainnet

```
npm run deploy:sepolia   # Sepolia testnet
npm run deploy:mainnet   # Ethereum mainnet
```

After deployment, register each module and its services in the `Registry` so other modules can discover them.
