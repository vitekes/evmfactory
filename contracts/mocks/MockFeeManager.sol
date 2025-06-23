// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

contract MockFeeManager {
    using SafeERC20 for IERC20;

    address public lastToken;
    uint256 public lastAmount;

    function depositFee(bytes32, address token, uint256 amount) external {
        lastToken = token;
        lastAmount = amount;
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }
}
