// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title PaymentContext
/// @notice Структура и функции для контекста платежа
library PaymentContext {
    enum ProcessingState {
        Initialized,
        Validating,
        Processing,
        Completed,
        Failed
    }

    struct Context {
        bytes32 moduleId;
        address sender;
        address recipient;
        address token;
        uint128 originalAmount;
        uint128 processedAmount;
        ProcessingState state;
        bool success;
        bytes metadata;
        bytes32 paymentId;
        string errorMessage;
    }

    function createContext(
        bytes32 moduleId,
        address sender,
        address recipient,
        address token,
        uint256 amount,
        bytes memory metadata
    ) internal view returns (Context memory) {
        require(amount <= type(uint128).max, 'Amount too large');
        Context memory ctx;
        ctx.moduleId = moduleId;
        ctx.sender = sender;
        ctx.recipient = recipient;
        ctx.token = token;
        ctx.originalAmount = uint128(amount);
        ctx.processedAmount = uint128(amount);
        ctx.state = ProcessingState.Initialized;
        ctx.success = false;
        ctx.metadata = metadata;
        ctx.paymentId = keccak256(abi.encode(moduleId, sender, recipient, token, amount, block.timestamp));
        ctx.errorMessage = '';
        return ctx;
    }

    function setState(Context memory ctx, ProcessingState newState) internal pure returns (Context memory) {
        ctx.state = newState;
        return ctx;
    }

    function setSuccess(Context memory ctx, bool success) internal pure returns (Context memory) {
        ctx.success = success;
        return ctx;
    }

    function setError(Context memory ctx, string memory errorMessage) internal pure returns (Context memory) {
        ctx.errorMessage = errorMessage;
        ctx.success = false;
        return ctx;
    }

    function updateProcessedAmount(Context memory ctx, uint256 amount) internal pure returns (Context memory) {
        require(amount <= type(uint128).max, 'Amount too large');
        ctx.processedAmount = uint128(amount);
        return ctx;
    }
}
