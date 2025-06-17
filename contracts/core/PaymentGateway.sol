// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccessControlCenter.sol";
import "./MultiValidator.sol";
import "./CoreFeeManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract PaymentGateway is ReentrancyGuard {
    using Address for address payable;

    AccessControlCenter public access;
    MultiValidator public validator;
    CoreFeeManager public feeManager;

    address public owner;

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
        require(msg.sender == owner, "not admin");
        _;
    }

    constructor(address accessControl, address validator_, address feeManager_) {
        access = AccessControlCenter(accessControl);
        validator = MultiValidator(validator_);
        feeManager = CoreFeeManager(feeManager_);
        owner = msg.sender;
    }

    function processPayment(
        bytes32 moduleId,
        address token,
        address payer,
        uint256 amount
    ) external onlyFeatureOwner nonReentrant returns (uint256 netAmount) {
        require(validator.isTokenAllowed(moduleId, token), "token not allowed");

        // Сбор комиссии (может быть 0)
        uint256 fee = feeManager.collect(moduleId, token, payer, amount);
        netAmount = amount - fee;

        emit PaymentProcessed(payer, token, amount, fee, netAmount, moduleId);
    }

    function setValidator(address newValidator) external onlyAdmin {
        validator = MultiValidator(newValidator);
    }

    function setFeeManager(address newManager) external onlyAdmin {
        feeManager = CoreFeeManager(newManager);
    }

    function setAccessControl(address newAccess) external onlyAdmin {
        access = AccessControlCenter(newAccess);
    }
}
