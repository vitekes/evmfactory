// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../interfaces/IPaymentProcessor.sol';
import '../PaymentContext.sol';
import '@openzeppelin/contracts/access/AccessControl.sol';

/// @title FeeProcessor
/// @notice Процессор для обработки комиссий
contract FeeProcessor is IPaymentProcessor, AccessControl {
    bytes32 public constant PROCESSOR_ADMIN_ROLE = keccak256('PROCESSOR_ADMIN_ROLE');

    string private constant PROCESSOR_NAME = 'FeeProcessor';
    string private constant PROCESSOR_VERSION = '1.0.0';

    uint16 public feePercent; // комиссия в базисных пунктах (например, 100 = 1%)

    constructor(uint16 initialFeePercent) {
        require(initialFeePercent <= 10000, 'FeeProcessor: fee percent too high');
        feePercent = initialFeePercent;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PROCESSOR_ADMIN_ROLE, msg.sender);
    }

    function isApplicable(bytes calldata) external pure override returns (bool applicable) {
        return true; // всегда применим
    }

    function process(
        bytes calldata contextBytes
    ) external view override returns (IPaymentProcessor.ProcessResult result, bytes memory updatedContextBytes) {
        PaymentContext.Context memory context = abi.decode(contextBytes, (PaymentContext.Context));

        uint256 feeAmount = (uint256(context.processedAmount) * feePercent) / 10000;

        if (feeAmount > context.processedAmount) {
            context = PaymentContext.setError(context, 'FeeProcessor: fee exceeds amount');
            return (IPaymentProcessor.ProcessResult.FAILED, abi.encode(context));
        }

        uint256 newAmount = uint256(context.processedAmount) - feeAmount;
        context = PaymentContext.updateProcessedAmount(context, newAmount);

        updatedContextBytes = abi.encode(context);
        return (IPaymentProcessor.ProcessResult.SUCCESS, updatedContextBytes);
    }

    function getName() external pure override returns (string memory) {
        return PROCESSOR_NAME;
    }

    function getVersion() external pure override returns (string memory) {
        return PROCESSOR_VERSION;
    }

    function configure(bytes32, bytes calldata configData) external override onlyRole(PROCESSOR_ADMIN_ROLE) {
        require(configData.length == 2, 'FeeProcessor: invalid config length');
        uint16 newFeePercent = (uint16(uint8(configData[0])) << 8) | uint16(uint8(configData[1]));
        require(newFeePercent <= 10000, 'FeeProcessor: fee percent too high');
        feePercent = newFeePercent;
    }
}
