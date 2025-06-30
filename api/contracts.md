# Contract Summary

A high level overview of the main Solidity contracts. See `contracts/` for sources.

- **AccessControlCenter** – centralized permissions management.
- **Registry** – keeps module and service addresses.
- **CoreFeeManager** – collects protocol fees.
- **PaymentGateway** – entry point for all payments.
- **MultiValidator** – aggregates validation strategies.
- **GasSubsidyManager** – optional gas subsidy mechanism.
- **ContestFactory** – deploys new ContestEscrow contracts.
- **ContestEscrow** – stores prize funds and distributes rewards.
- **Marketplace** – basic marketplace for item sales.
- **MarketplaceFactory** – deploys marketplace instances.
- **SubscriptionManager** – recurring subscription management.
