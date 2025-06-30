# Coverage Guidelines

To measure contract coverage with Foundry, run:

```bash
forge coverage --report lcov --ir-minimum
bash scripts/check-coverage.sh 90
```

The `foundry.toml` file defines `no_match_coverage` patterns to skip mocks and optional modules from coverage calculations. Adjust this list to include only the contracts you want to track.

New tests were added to improve coverage for `ContestEscrow` and a new suite `ContestValidator.t.sol`.
