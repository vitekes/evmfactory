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

    // ------------------------------------------------------------------
    // Core service identifiers
    // ------------------------------------------------------------------
    bytes32 internal constant SERVICE_ACCESS_CONTROL = keccak256('AccessControlCenter');
    bytes32 internal constant SERVICE_REGISTRY = keccak256('Registry');
    bytes32 internal constant SERVICE_FEE_MANAGER = keccak256('FeeManager');
    bytes32 internal constant SERVICE_PAYMENT_GATEWAY = keccak256('PaymentGateway');

    // ------------------------------------------------------------------
    // Module service identifiers
    // ------------------------------------------------------------------
    bytes32 internal constant SERVICE_VALIDATOR = keccak256('Validator');
    bytes32 internal constant SERVICE_PRICE_ORACLE = keccak256('PriceOracle');
    bytes32 internal constant SERVICE_PERMIT2 = keccak256('Permit2');
    bytes32 internal constant SERVICE_NFT_MANAGER = keccak256('NFTManager');

    // ------------------------------------------------------------------
    // Access control roles
    // ------------------------------------------------------------------
    bytes32 internal constant FEATURE_OWNER_ROLE = keccak256('FEATURE_OWNER_ROLE');
    bytes32 internal constant OPERATOR_ROLE = keccak256('OPERATOR_ROLE');
    bytes32 internal constant RELAYER_ROLE = keccak256('RELAYER_ROLE');
    bytes32 internal constant MODULE_ROLE = keccak256('MODULE_ROLE');
    bytes32 internal constant AUTOMATION_ROLE = keccak256('AUTOMATION_ROLE');
    bytes32 internal constant GOVERNOR_ROLE = keccak256('GOVERNOR_ROLE');

    // ------------------------------------------------------------------
    // Common time constants
    // ------------------------------------------------------------------
    uint256 internal constant SECONDS_PER_DAY = 86400;
    uint256 internal constant SECONDS_PER_WEEK = 604800;
    uint256 internal constant SECONDS_PER_MONTH = 2592000; // 30 days
    uint256 internal constant SECONDS_PER_YEAR = 31536000; // 365 days
}
