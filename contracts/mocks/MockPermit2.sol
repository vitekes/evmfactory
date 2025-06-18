// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockPermit2 {
    using SafeERC20 for IERC20;

    struct TokenPermissions {
        address token;
        uint256 amount;
    }

    struct PermitTransferFrom {
        TokenPermissions permitted;
        uint256 nonce;
        uint256 deadline;
    }

    struct SignatureTransferDetails {
        address to;
        uint256 requestedAmount;
    }

    mapping(address => uint256) public nonces;

    function permitTransferFrom(
        PermitTransferFrom calldata permit,
        SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes calldata
    ) external {
        require(block.timestamp <= permit.deadline, "expired");
        nonces[owner] = permit.nonce + 1;
        IERC20(permit.permitted.token).safeTransferFrom(owner, transferDetails.to, transferDetails.requestedAmount);
    }
}
