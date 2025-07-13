// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../pay/interfaces/IPaymentGateway.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

contract MockPaymentGateway is IPaymentGateway {
    using SafeERC20 for IERC20;

    function processPayment(
        bytes32,
        address token,
        address payer,
        uint256 amount,
        bytes calldata
    ) external payable override returns (uint256 netAmount) {
        if (token == address(0)) {
            require(msg.value >= amount, 'insufficient value');
            payable(msg.sender).transfer(amount);
        } else {
            IERC20(token).safeTransferFrom(payer, msg.sender, amount);
        }
        return amount;
    }

    function convertAmount(bytes32, address, address, uint256 amount) external pure override returns (uint256) {
        return amount;
    }

    function isPairSupported(bytes32, address, address) external pure override returns (bool) {
        return true;
    }

    function getSupportedTokens(bytes32) external pure override returns (address[] memory tokens) {
        tokens = new address[](0);
    }

    function getPaymentStatus(bytes32) external pure override returns (uint8) {
        return 1;
    }
}
