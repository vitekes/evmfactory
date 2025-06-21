// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IPaymentGateway {
    function feeManager() external view returns (address);
}
