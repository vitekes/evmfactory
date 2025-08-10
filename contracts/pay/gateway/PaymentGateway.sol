// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../interfaces/IPaymentGateway.sol';
import '../interfaces/IPaymentProcessor.sol';
import '../interfaces/IProcessorRegistry.sol';
import '../PaymentContext.sol';
import '../registry/ProcessorRegistry.sol';
import '../orchestrator/PaymentOrchestrator.sol';
import '../processors/TokenFilterProcessor.sol';
import '../../errors/Errors.sol';
import '@openzeppelin/contracts/access/AccessControl.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/Pausable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/// @title PaymentGateway
/// @notice Платёжный шлюз для приёма и маршрутизации платежей
contract PaymentGateway is IPaymentGateway, AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant PAYMENT_ADMIN_ROLE = keccak256('PAYMENT_ADMIN_ROLE');
    bytes32 public constant PAUSER_ROLE = keccak256('PAUSER_ROLE');

    string private constant GATEWAY_NAME = 'PaymentGateway';
    string private constant GATEWAY_VERSION = '1.0.0';

    PaymentOrchestrator public orchestrator;

    mapping(bytes32 => uint8) private paymentStatuses;

    event PaymentProcessed(
        bytes32 indexed moduleId,
        bytes32 indexed paymentId,
        address indexed token,
        address payer,
        uint256 amount,
        uint256 netAmount,
        uint8 status
    );

    constructor(address orchestratorAddress) {
        if (orchestratorAddress == address(0)) revert ZeroAddress();
        orchestrator = PaymentOrchestrator(orchestratorAddress);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAYMENT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    function processPayment(
        bytes32 moduleId,
        address token,
        address payer,
        uint256 amount,
        bytes calldata signature
    ) external payable nonReentrant whenNotPaused returns (uint256 netAmount) {
        if (amount == 0) revert InvalidAmount();

        bool isNative = token == address(0);
        uint256 actualAmount = amount;

        if (isNative) {
            if (msg.value < amount) revert InsufficientBalance();
        } else {
            uint256 beforeBal = IERC20(token).balanceOf(address(this));
            IERC20(token).safeTransferFrom(payer, address(this), amount);
            uint256 afterBal = IERC20(token).balanceOf(address(this));
            actualAmount = afterBal - beforeBal;
            if (actualAmount == 0) revert TransferFailed();
        }

        (uint256 netAmount_, bytes32 paymentId_, , ) = orchestrator.processPayment(
            moduleId,
            token,
            payer,
            actualAmount,
            signature
        );

        require(paymentStatuses[paymentId_] == 0, "Payment already processed");
        paymentStatuses[paymentId_] = 1; // success

        if (isNative) {
            // Для нативного токена оставляем netAmount в контракте для Marketplace
            // Возвращаем только избыток, если msg.value больше amount
            uint256 excess = msg.value - amount;
            if (excess > 0) {
                (bool success, ) = payable(payer).call{value: excess}('');
                if (!success) revert TransferFailed();
            }
        }
        // Для ERC20 токенов комиссии остаются в контракте gateway

        // Отправляем netAmount обратно вызывающему контракту (Marketplace)
        if (isNative && netAmount_ > 0) {
            (bool success, ) = payable(msg.sender).call{value: netAmount_}('');
            if (!success) revert TransferFailed();
        } else if (!isNative && netAmount_ > 0) {
            IERC20(token).safeTransfer(msg.sender, netAmount_);
        }

        emit PaymentProcessed(moduleId, paymentId_, token, payer, amount, netAmount_, 1);

        return netAmount_;
    }

    function convertAmount(
        bytes32 moduleId,
        address fromToken,
        address toToken,
        uint256 amount
    ) external view override returns (uint256 convertedAmount) {
        return orchestrator.convertAmount(moduleId, fromToken, toToken, amount);
    }

    function isPairSupported(
        bytes32 moduleId,
        address fromToken,
        address toToken
    ) external view override returns (bool isSupported) {
        return orchestrator.isPairSupported(moduleId, fromToken, toToken);
    }

    function getSupportedTokens(bytes32 moduleId) external view override returns (address[] memory tokens) {
        address[] memory processors = orchestrator.getProcessors(moduleId);
        address tokenFilterProcessor = address(0);
        for (uint256 i = 0; i < processors.length; i++) {
            try IPaymentProcessor(processors[i]).getName() returns (string memory name) {
                if (keccak256(abi.encodePacked(name)) == keccak256(abi.encodePacked('TokenFilter'))) {
                    tokenFilterProcessor = processors[i];
                    break;
                }
            } catch {
                continue;
            }
        }
        if (tokenFilterProcessor != address(0)) {
            try TokenFilterProcessor(tokenFilterProcessor).getAllowedTokens(moduleId) returns (
                address[] memory allowedTokens
            ) {
                return allowedTokens;
            } catch {
                return new address[](0);
            }
        }
        return new address[](0);
    }

    function getPaymentStatus(bytes32 paymentId) external view override returns (uint8 status) {
        return paymentStatuses[paymentId];
    }

    function getName() external pure returns (string memory) {
        return GATEWAY_NAME;
    }

    function getVersion() external pure returns (string memory) {
        return GATEWAY_VERSION;
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}
