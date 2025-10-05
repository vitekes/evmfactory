# EVM Factory Monorepo

This repository now groups multiple blockchain targets under a single tree:

- `evm/` ? Hardhat project with Solidity contracts, Ignition modules, demos, and tests.
- `solana/` ? Anchor workspace and TypeScript tests that implement the Solana port.
- `move/` ? placeholder for future Move-based implementation.
- `docs/` ? shared documentation that applies across targets.

To work with a specific target, switch into its folder and follow the local README instructions.

```bash
cd evm   # or solana
```

The EVM package retains the original npm scripts for compilation, testing, deployments, and demos. The Solana workspace includes Anchor configuration plus TypeScript helpers/tests; install its toolchain separately (Rust + Anchor CLI) before running `anchor test`.

Shared CI configuration and hooks are left at the repository root (`.github/`, `.husky/`). Adjust or extend them as you wire additional targets.
