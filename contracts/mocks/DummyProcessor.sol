// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../payments/BaseProcessor.sol";
import "../payments/PaymentContextLibrary.sol";

contract DummyProcessor is BaseProcessor {
    using PaymentContextLibrary for PaymentContextLibrary.PaymentContext;

    function getName() public pure override returns (string memory name) {
        return "Dummy";
    }

    function getVersion() public pure override returns (string memory version) {
        return "1.0";
    }

    function _processInternal(
        PaymentContextLibrary.PaymentContext memory context
    ) internal override returns (ProcessResult result, bytes memory updatedContext) {
        context.packed.success = true;
        context = PaymentContextLibrary.addProcessorResult(context, getName(), uint8(ProcessResult.SUCCESS));
        return (ProcessResult.SUCCESS, abi.encode(context));
    }

    function _isApplicableInternal(
        PaymentContextLibrary.PaymentContext memory /*context*/
    ) internal pure override returns (bool applicable) {
        return true;
    }
}
