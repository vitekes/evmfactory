// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPaymentGateway} from '../pay/interfaces/IPaymentGateway.sol';

contract GatewayCaller {
    function payTwice(address gateway, bytes32 moduleId, address token, address payer, uint256 amount) external {
        IPaymentGateway(gateway).processPayment(moduleId, token, payer, amount, '');
        IPaymentGateway(gateway).processPayment(moduleId, token, payer, amount, '');
    }
}
