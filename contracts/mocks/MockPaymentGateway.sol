// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../interfaces/IGateway.sol';
import '../interfaces/IRegistry.sol';
import '../interfaces/IEventRouter.sol';
import '../interfaces/CoreDefs.sol';
import '../errors/Errors.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '../utils/Native.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

/// @title MockPaymentGateway
/// @notice Test implementation of payment gateway interface
/// @dev Used only for testing, not for production use
contract MockPaymentGateway is IGateway, ReentrancyGuard {
    /// @notice Получить цену в указанной валюте
    /// @param amount Сумма в исходном токене
    /// @return price Цена в целевом токене
    function getPriceInCurrency(
        bytes32 /* moduleId */,
        address /* fromToken */,
        address /* toToken */,
        uint256 amount
    ) external pure override returns (uint256 price) {
        // Простая реализация для мока
        return amount;
    }
    using SafeERC20 for IERC20;
    using Native for address;

    IRegistry public registry;
    uint256 public feePercent = 5; // 5% default fee

    // Accumulated fees per token
    mapping(address => uint256) public accruedFees;

    event PaymentProcessed(
        address indexed payer,
        address indexed token,
        uint256 grossAmount,
        uint256 fee,
        uint256 netAmount,
        bytes32 moduleId
    );

    constructor(address _registry) {
        require(_registry != address(0), 'Registry cannot be zero address');
        registry = IRegistry(_registry);
    }

    /// @notice Gets price in preferred currency
    /// @param /* moduleId */ Module ID (unused)
    /// @param baseToken Base token
    /// @param paymentToken Payment token
    /// @param baseAmount Amount in base token
    /// @return paymentAmount Amount in payment token
    function getPriceInPreferredCurrency(
        bytes32 /* moduleId */,
        address baseToken,
        address paymentToken,
        uint256 baseAmount
    ) external pure returns (uint256 paymentAmount) {
        // In test gateway, simply return the same amount for identical tokens
        // or a conditional value for different tokens
        if (baseToken == paymentToken) {
            return baseAmount;
        }

        // For testing, use a simple conversion
        return baseAmount * 2; // Conditional conversion for testing
    }

    /// @notice Checks if token pair is supported
    /// @param /* moduleId */ Module ID (unused)
    /// @param /* baseToken */ Base token (unused)
    /// @param /* paymentToken */ Payment token (unused)
    /// @return supported Whether the pair is supported
    function isPairSupported(
        bytes32 /* moduleId */,
        address /* baseToken */,
        address /* paymentToken */
    ) external pure returns (bool supported) {
        // In test, all pairs are supported
        return true;
    }

    /// @notice Converts amount between tokens
    /// @param /* moduleId */ Module ID (unused)
    /// @param baseToken Base token
    /// @param paymentToken Payment token
    /// @param baseAmount Amount in base token
    /// @return paymentAmount Amount in payment token
    function convertAmount(
        bytes32 /* moduleId */,
        address baseToken,
        address paymentToken,
        uint256 baseAmount
    ) external pure returns (uint256 paymentAmount) {
        // Check for zero amount
        if (baseAmount == 0) return 0;

        // Check for identical tokens
        if (baseToken == paymentToken) {
            return baseAmount;
        }

        // More realistic conversion logic for tests
        // Use different coefficients based on token addresses
        uint256 conversionFactor;
        // Use hash of the last byte of the address to simulate different exchange rates
        uint8 lastByte = uint8(uint160(paymentToken) & 0xFF);
        if (lastByte > 200) {
            conversionFactor = 3;
        } else if (lastByte > 100) {
            conversionFactor = 2;
        } else {
            conversionFactor = 1;
        }

        // Check for overflow
        if (baseAmount > type(uint256).max / conversionFactor) {
            revert Overflow();
        }

        return baseAmount * conversionFactor;
    }

    /// @notice Processes payment
    /// @param moduleId Module ID
    /// @param token Payment token (0x0 or ETH_SENTINEL for native currency)
    /// @param payer Payer address
    /// @param amount Payment amount
    /// @return netAmount Net amount after fee deduction
    function processPayment(
        bytes32 moduleId,
        address token,
        address payer,
        uint256 amount,
        bytes calldata /* signature */
    ) external payable nonReentrant returns (uint256 netAmount) {
        // Базовые проверки параметров
        if (payer == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();

        // Calculate fee - avoid unnecessary calculations with zero fee
        uint256 fee = 0;
        if (feePercent > 0) {
            // Check for overflow when calculating fee
            if (amount > type(uint256).max / feePercent) {
                revert Overflow();
            }
            fee = (amount * feePercent) / 100;

            // Ensure fee doesn't exceed payment amount
            if (fee > amount) {
                revert FeeExceedsAmount();
            }
        }
        netAmount = amount - fee;

        // Process payment based on token type
        if (token.isNative()) {
            // Handle native currency (ETH)
            if (msg.value < amount) revert InsufficientBalance();

            // Handle refund if excess ETH was sent
            uint256 excess = msg.value - amount;
            if (excess > 0) {
                (bool refundSuccess, ) = payable(payer).call{value: excess}('');
                if (!refundSuccess) revert RefundDisabled();
            }

            // Track fee for later withdrawal
            accruedFees[address(0)] += fee;

            // The calling contract is responsible for transferring the netAmount
            // We don't automatically transfer ETH to avoid reentrancy risks
        } else {
            // Handle ERC20 tokens
            // Cache addresses and objects to minimize storage access
            IERC20 tokenContract = IERC20(token);
            address self = address(this);
            address caller = msg.sender;

            // Transfer tokens from payer to gateway
            tokenContract.safeTransferFrom(payer, self, amount);

            // Track fee for later withdrawal
            accruedFees[token] += fee;

            // Transfer net amount to calling contract using cached values
            tokenContract.safeTransfer(caller, netAmount);
        }

        // Send event through EventRouter or local event
        address router = registry.getModuleServiceByAlias(moduleId, 'EventRouter');
        if (router != address(0)) {
            bytes memory eventData = abi.encode(
                payer, // Payer
                token, // Token
                amount, // Gross amount
                fee, // Fee
                netAmount, // Net amount
                moduleId, // Module ID
                uint16(1) // Version
            );
            IEventRouter(router).route(IEventRouter.EventKind.PaymentProcessed, eventData);
        } else {
            emit PaymentProcessed(payer, token, amount, fee, netAmount, moduleId);
        }

        return netAmount;
    }

    /// @notice Sets fee percentage
    /// @param percent New fee percentage
    function setFeePercent(uint256 percent) external {
        // Check for reasonable fee limit and provide detailed error message
        if (percent > 100) revert FeeTooHigh();

        // Track fee changes
        feePercent = percent;

        // Here we could add an event for audit purposes
        // emit FeePercentChanged(oldFeePercent, percent);
    }

    /// @notice Withdraws accumulated fees for a token
    /// @param token Token address (0x0 for native currency)
    /// @param to Recipient address
    function withdrawFees(address token, address to) external nonReentrant {
        if (to == address(0)) revert ZeroAddress();

        uint256 amount = accruedFees[token];
        if (amount == 0) revert NothingToWithdraw();

        // Reset before transfer to prevent reentrancy
        accruedFees[token] = 0;

        if (token.isNative()) {
            // Transfer native currency
            (bool success, ) = payable(to).call{value: amount}('');
            if (!success) revert RefundDisabled();
        } else {
            // Transfer ERC20 token
            IERC20(token).safeTransfer(to, amount);
        }
    }

    /// @notice Allows the contract to receive ETH
    receive() external payable {}

    /// @notice Fallback function to handle direct ETH transfers
    fallback() external payable {}

    /// @notice Helper function for legacy compatibility
    /// @dev This was removed to avoid function overloading issues
    /// Use getPriceInCurrency or the other convertAmount implementation instead
}
