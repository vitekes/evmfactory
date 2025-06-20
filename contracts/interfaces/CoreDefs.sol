// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title CoreDefs
/// @notice Common core constants used across modules
library CoreDefs {
    bytes32 internal constant SERVICE_PAYMENT_GATEWAY = keccak256('PaymentGateway');
    bytes32 internal constant SERVICE_VALIDATOR = keccak256('Validator');
    bytes32 internal constant CONTEST_MODULE_ID = keccak256('Contest');
}
