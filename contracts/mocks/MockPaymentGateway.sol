// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockPaymentGateway {
    using SafeERC20 for IERC20;

    function processPayment(bytes32, address token, address payer, uint256 amount, bytes calldata) external returns (uint256) {
        IERC20(token).safeTransferFrom(payer, msg.sender, amount);
        return amount;
    }
}
