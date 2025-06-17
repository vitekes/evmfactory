// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccessControlCenter.sol";
import "./TokenRegistry.sol";
import "./CoreFeeManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract PaymentGateway is ReentrancyGuard {
    using Address for address payable;
    using SafeERC20 for IERC20;

    AccessControlCenter public access;
    TokenRegistry public tokenRegistry;
    CoreFeeManager public feeManager;


    event PaymentProcessed(
        address indexed payer,
        address indexed token,
        uint256 grossAmount,
        uint256 fee,
        uint256 netAmount,
        bytes32 moduleId
    );

    modifier onlyFeatureOwner() {
        require(access.hasRole(access.FEATURE_OWNER_ROLE(), msg.sender), "not feature owner");
        _;
    }

    modifier onlyAdmin() {
        require(access.hasRole(access.DEFAULT_ADMIN_ROLE(), msg.sender), "not admin");
        _;
    }

    constructor(address accessControl, address validator_, address feeManager_) {
        access = AccessControlCenter(accessControl);
        tokenRegistry = TokenRegistry(validator_);
        feeManager = CoreFeeManager(feeManager_);
    }

    function processPayment(
        bytes32 moduleId,
        address token,
        address payer,
        uint256 amount
    ) external onlyFeatureOwner nonReentrant returns (uint256 netAmount) {
        require(tokenRegistry.isTokenAllowed(moduleId, token), "token not allowed");

        IERC20(token).safeTransferFrom(payer, address(this), amount);
        IERC20(token).forceApprove(address(feeManager), amount);
        uint256 fee = feeManager.collect(moduleId, token, address(this), amount);
        IERC20(token).forceApprove(address(feeManager), 0);
        netAmount = amount - fee;
        IERC20(token).safeTransfer(msg.sender, netAmount);

        emit PaymentProcessed(payer, token, amount, fee, netAmount, moduleId);
    }

    function setValidator(address newValidator) external onlyAdmin {
        tokenRegistry = TokenRegistry(newValidator);
    }

    function setFeeManager(address newManager) external onlyAdmin {
        feeManager = CoreFeeManager(newManager);
    }

    function setAccessControl(address newAccess) external onlyAdmin {
        access = AccessControlCenter(newAccess);
    }
}
