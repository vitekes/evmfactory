// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../interfaces/IPaymentProcessor.sol';
import '../PaymentContext.sol';
import '@openzeppelin/contracts/access/AccessControl.sol';

/// @title OracleProcessor
/// @notice Sample payment processor stub that simply echoes the requested amount
contract OracleProcessor is IPaymentProcessor, AccessControl {
    bytes32 public constant PROCESSOR_ADMIN_ROLE = keccak256('PROCESSOR_ADMIN_ROLE');

    string private constant PROCESSOR_NAME = 'PriceOracle';
    string private constant PROCESSOR_VERSION = '1.0.0';

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PROCESSOR_ADMIN_ROLE, msg.sender);
    }

    function isApplicable(bytes calldata) external pure override returns (bool applicable) {
        return true;
    }

    function process(
        bytes calldata contextBytes
    ) external pure override returns (IPaymentProcessor.ProcessResult result, bytes memory updatedContextBytes) {
        PaymentContext.Context memory context = abi.decode(contextBytes, (PaymentContext.Context));
        updatedContextBytes = abi.encode(context);
        return (IPaymentProcessor.ProcessResult.SUCCESS, updatedContextBytes);
    }

    function getName() external pure override returns (string memory) {
        return PROCESSOR_NAME;
    }

    function getVersion() external pure override returns (string memory) {
        return PROCESSOR_VERSION;
    }

    function configure(bytes32, bytes calldata) external override onlyRole(PROCESSOR_ADMIN_ROLE) {
        // no-op for demo implementation
    }

    function convertAmount(bytes32, address, address, uint256 amount) external pure returns (uint256) {
        return amount;
    }
}
