// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title CoreDefs
/// @notice Common core constants used across modules
library CoreDefs {
    // ------------------------------------------------------------------
    // Module identifiers (MODULE_ID)
    // ------------------------------------------------------------------
    bytes32 internal constant MARKETPLACE_MODULE_ID = keccak256('Marketplace');
    bytes32 internal constant SUBSCRIPTION_MODULE_ID = keccak256('SubscriptionManager');
    bytes32 internal constant CONTEST_MODULE_ID = keccak256('Contest');
    bytes32 internal constant DONATE_MODULE_ID = keccak256('Donate');
    bytes32 internal constant MONETARY_CASH_MODULE_ID = keccak256('MonetaryCash');

    // Упразднили константы сервисов - теперь используем строковые алиасы напрямую

    // ------------------------------------------------------------------
    // Access control roles
    // ------------------------------------------------------------------
    bytes32 internal constant FEATURE_OWNER_ROLE = keccak256('FEATURE_OWNER_ROLE');
    bytes32 internal constant OPERATOR_ROLE = keccak256('OPERATOR_ROLE');
    bytes32 internal constant RELAYER_ROLE = keccak256('RELAYER_ROLE');
    bytes32 internal constant MODULE_ROLE = keccak256('MODULE_ROLE');
    bytes32 internal constant AUTOMATION_ROLE = keccak256('AUTOMATION_ROLE');
    bytes32 internal constant GOVERNOR_ROLE = keccak256('GOVERNOR_ROLE');
    bytes32 internal constant AUTHOR_ROLE = keccak256('AUTHOR_ROLE');

    // ------------------------------------------------------------------
    // Common time constants
    // ------------------------------------------------------------------
    uint256 internal constant SECONDS_PER_DAY = 86400;
    uint256 internal constant SECONDS_PER_WEEK = 604800;
    uint256 internal constant SECONDS_PER_MONTH = 2592000; // 30 days
    uint256 internal constant SECONDS_PER_YEAR = 31536000; // 365 days
}
