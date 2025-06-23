// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '../interfaces/IGateway.sol';

contract MockPaymentGateway is IGateway {
    using SafeERC20 for IERC20;

    address public feeManagerAddress;

    function setFeeManager(address manager) external {
        feeManagerAddress = manager;
    }

    function feeManager() external view returns (address) {
        return feeManagerAddress;
    }

    function processPayment(
        bytes32,
        address token,
        address payer,
        uint256 amount,
        bytes calldata
    ) external returns (uint256) {
        IERC20(token).safeTransferFrom(payer, msg.sender, amount);
        return amount;
    }
}
