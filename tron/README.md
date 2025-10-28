# Tron Workspace

This package lifts the existing EVM Factory contracts onto the Tron network. It reuses the Solidity sources from `../evm/contracts` and provides a TypeScript toolchain for compiling and deploying them with TronWeb.

## Getting started

1. Install dependencies:
   ```bash
   cd tron
   npm install
   ```
2. Create a local environment file and fill in the endpoints + key material:
   ```bash
   cp .env.example .env
   ```
   - `TRON_FULL_NODE`, `TRON_SOLIDITY_NODE`, `TRON_EVENT_SERVER` point to your node (defaults target the Shasta testnet).
   - `TRON_PRIVATE_KEY` is the signer used by the deployment and automation scripts. Store it safely.
   - Optional overrides: `TRON_OWNER_ADDRESS`, `TRON_FEE_LIMIT`, `TRON_CALL_VALUE`, `TRON_API_KEY` for TronGrid.

## Compile the contracts

```
npm run compile
```

The compiler script (`scripts/compile.ts`) gathers Solidity sources from:
- `tron/contracts` (place Tron-only overrides here if you need network specific tweaks).
- `../evm/contracts` (shared core contracts).

It produces Hardhat-style artifacts under `tron/artifacts/` and stores the raw solc input/output in `tron/cache/` for debugging.

## Deploy to Tron

```
npm run deploy -- \
  --artifact contracts/modules/subscriptions/SubscriptionManager.sol/SubscriptionManager.json \
  --args-file deployments/subscription.constructor.json \
  --save deployments/subscription.deployed.json
```

- `--artifact` is the path to the generated artifact relative to `tron/artifacts/`.
- Provide constructor arguments either with `--args '["0x..."]'` (JSON array) or with `--args-file`.
- Arguments loaded from a file may be a bare JSON array or an object with `args`/`parameters`.
- Base58 (T...) addresses are automatically converted to hex before submission; hex inputs are left untouched.
- Use `--save <path>` to persist the deployment metadata for later scripts.

### Example constructor file (`deployments/subscription.constructor.json`)
```json
{
  "args": [
    "0x41f...",
    "TX1...",
    "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
  ]
}
```

Поле `args[0]` описывает адрес CoreSystem на Tron, `args[1]` - TRC-20 платёжный шлюз (можно указывать в base58), `args[2]` - хэш или байтовую строку для третьего аргумента конструктора.

### Working with TRC-20 approvals

TRC-20 tokens keep the same ABI as ERC-20. To support subscription renewals:
1. Collect the initial `approve` signed by the user on the front-end (`tronweb.trx.sign` in-wallet).
2. On the backend, verify the transaction receipt and confirm `allowance(subscriber, gateway)` is set.
3. Persist both the approval txid and the first `subscribe` txid.
4. For auto-renewals, Celery (or your scheduler) can call a service that uses `tronWeb.contract(abi, address)` to execute `charge`. Use the private key from `.env` inside a secure vault.
5. Before charging, re-check `allowance`; if it was lowered or revoked, pause the subscription and notify the user.

### Verifying transactions server-side

```ts
import TronWeb from "tronweb";

const tronWeb = new TronWeb({
  fullNode: process.env.TRON_FULL_NODE!,
  solidityNode: process.env.TRON_SOLIDITY_NODE!,
  eventServer: process.env.TRON_EVENT_SERVER!,
  privateKey: process.env.TRON_PRIVATE_KEY!,
});

const receipt = await tronWeb.trx.getTransactionInfo(txid);
if (receipt && receipt.result === "SUCCESS") {
  // persist the subscription in your database
}
```

## Project layout

- `contracts/` — optional Tron-specific Solidity overrides. Leave empty to consume the shared EVM sources.
- `scripts/compile.ts` — compiles everything with solc 0.8.28 using viaIR+optimizer (same settings as Hardhat).
- `scripts/deploy.ts` — CLI deploy helper built on TronWeb.
- `deployments/` — recommended location for constructor argument files and deployment logs (create as needed).

## Next steps

- Add integration tests that call the deployed contracts through TronWeb.
- Mirror the existing Hardhat Ignition flows in Tron (e.g. scripted deployments for production environments).
- Extend the backend to index Tron events via the event server API (`/event/contract/{address}`) or a dedicated indexer.
- Wire Celery jobs for recurring `charge` calls once allowances are in place.
