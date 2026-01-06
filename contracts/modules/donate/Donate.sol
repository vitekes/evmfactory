// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../../core/CoreSystem.sol';
import '../../errors/Errors.sol';
import '../../pay/interfaces/IPaymentGateway.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

/// @title Donate
/// @notice Simple donation module that routes payments through the shared payment gateway
contract Donate is ReentrancyGuard {
    using SafeERC20 for IERC20;

    CoreSystem public immutable core;
    IPaymentGateway public immutable paymentGateway;
    bytes32 public immutable MODULE_ID;

    uint256 private _donationCounter;

    address internal constant NATIVE_TOKEN_ALIAS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    event DonationProcessed(
        uint256 indexed donationId,
        address indexed donor,
        address indexed recipient,
        address token,
        uint256 grossAmount,
        uint256 netAmount,
        bytes32 metadata,
        uint256 timestamp,
        bytes32 moduleId
    );

    modifier onlyAdmin() {
        if (!core.hasRole(core.DEFAULT_ADMIN_ROLE(), msg.sender)) revert NotAdmin();
        _;
    }

    constructor(address _core, address _paymentGateway, bytes32 moduleId) {
        if (_core == address(0)) revert ZeroAddress();
        if (_paymentGateway == address(0)) revert ZeroAddress();
        if (moduleId == bytes32(0)) revert InvalidArgument();

        core = CoreSystem(_core);
        paymentGateway = IPaymentGateway(_paymentGateway);
        MODULE_ID = moduleId;
    }

    function donationCount() external view returns (uint256) {
        return _donationCounter;
    }

    function donate(
        address recipient,
        address token,
        uint256 amount,
        bytes32 metadata
    ) external payable nonReentrant returns (uint256 donationId) {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert AmountZero();

        (address paymentToken, bool isNative) = _normalizeToken(token);

        uint256 netAmount;

        if (isNative) {
            if (msg.value < amount) revert InsufficientBalance();

            netAmount = paymentGateway.processPayment{value: amount}(MODULE_ID, address(0), msg.sender, amount, '');

            if (netAmount > amount) revert InvalidState();

            _sendNative(recipient, netAmount);

            uint256 change = msg.value - amount;
            if (change > 0) {
                _sendNative(msg.sender, change);
            }
        } else {
            netAmount = paymentGateway.processPayment(MODULE_ID, paymentToken, msg.sender, amount, '');

            if (netAmount > amount) revert InvalidState();

            IERC20(paymentToken).safeTransfer(recipient, netAmount);
        }

        donationId = ++_donationCounter;

        emit DonationProcessed(
            donationId,
            msg.sender,
            recipient,
            paymentToken,
            amount,
            netAmount,
            metadata,
            block.timestamp,
            MODULE_ID
        );
    }

    function getSupportedTokens() external view returns (address[] memory tokens) {
        return paymentGateway.getSupportedTokens(MODULE_ID);
    }

    function rescueTokens(address token, address to, uint256 amount) external onlyAdmin nonReentrant {
        if (to == address(0)) revert ZeroAddress();

        if (token == address(0)) {
            _sendNative(to, amount);
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    receive() external payable {}

    fallback() external payable {
        revert('Donate: unsupported call');
    }

    function _normalizeToken(address token) internal pure returns (address normalized, bool isNative) {
        if (token == address(0) || token == NATIVE_TOKEN_ALIAS) {
            return (address(0), true);
        }
        return (token, false);
    }

    function _sendNative(address to, uint256 amount) internal {
        if (amount == 0) return;
        (bool success, ) = payable(to).call{value: amount}('');
        if (!success) revert TransferFailed();
    }
}
