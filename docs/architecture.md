# Architecture

This project consists of a small core with optional modules that extend the base functionality. All contracts rely on a single `CoreSystem` for role management and service discovery.

## Core contracts

- **CoreSystem** – centralized RBAC and service registry.
- **Registry** – registry of modules and shared services.
- **CoreFeeManager** – collects protocol and module fees.
- **PaymentGateway** – handles all user payments.
- **MultiValidator** – aggregator for token and address validators.
- **GasSubsidyManager** – subsidizes transaction gas for certain users.

## Modules

- **ContestFactory & ContestEscrow** – create contests and manage prize payouts.
- **Marketplace & MarketplaceFactory** – sell items and subscriptions.
- **SubscriptionManager** – track subscription status and recurring charges.

Each module registers its contracts in the `Registry` and relies on the gateway and validators from the core. New modules can be integrated by deploying their contracts and adding them to the registry.
