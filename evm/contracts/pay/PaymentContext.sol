// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title PaymentContext
/// @notice Shared payment processing state passed between payment processors
library PaymentContext {
    enum ProcessingState {
        Initialized,
        Validating,
        Processing,
        Completed,
        Failed
    }

    struct FeeInfo {
        address recipient;
        uint128 amount;
    }

    struct Context {
        bytes32 moduleId;
        address sender;
        address recipient;
        address token;
        uint128 originalAmount;
        uint128 payerAmount;
        uint128 processedAmount;
        ProcessingState state;
        bool success;
        bytes metadata;
        bytes32 paymentId;
        FeeInfo[] fees;
        string errorMessage;
    }

    function createContext(
        bytes32 moduleId,
        address sender,
        address recipient,
        address token,
        uint256 amount,
        uint256 nonceValue,
        bytes memory metadata
    ) internal view returns (Context memory) {
        require(amount <= type(uint128).max, 'Amount too large');
        Context memory ctx;
        ctx.moduleId = moduleId;
        ctx.sender = sender;
        ctx.recipient = recipient;
        ctx.token = token;
        ctx.originalAmount = uint128(amount);
        ctx.payerAmount = uint128(amount);
        ctx.processedAmount = uint128(amount);
        ctx.state = ProcessingState.Initialized;
        ctx.success = false;
        ctx.metadata = metadata;
        ctx.paymentId = keccak256(
            abi.encode(moduleId, sender, recipient, token, amount, nonceValue, block.chainid, address(this))
        );
        ctx.errorMessage = '';
        ctx.fees = new FeeInfo[](0);
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

    function setPayerAmount(Context memory ctx, uint256 amount) internal pure returns (Context memory) {
        require(amount <= type(uint128).max, 'Amount too large');
        ctx.payerAmount = uint128(amount);
        return ctx;
    }

    function addFee(Context memory ctx, address recipient, uint256 amount) internal pure returns (Context memory) {
        require(recipient != address(0), 'Invalid recipient');
        require(amount <= type(uint128).max, 'Amount too large');

        uint256 currentLength = ctx.fees.length;
        FeeInfo[] memory updatedFees = new FeeInfo[](currentLength + 1);
        for (uint256 i = 0; i < currentLength; i++) {
            updatedFees[i] = ctx.fees[i];
        }
        updatedFees[currentLength] = FeeInfo({recipient: recipient, amount: uint128(amount)});
        ctx.fees = updatedFees;
        return ctx;
    }

    function totalFees(Context memory ctx) internal pure returns (uint256 total) {
        for (uint256 i = 0; i < ctx.fees.length; i++) {
            total += ctx.fees[i].amount;
        }
    }
}
