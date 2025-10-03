// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import '../../core/BaseFactory.sol';

import './ContestEscrow.sol';

import './shared/PrizeInfo.sol';

import './interfaces/IContestValidator.sol';

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import '../../core/CoreDefs.sol';

/// @title ContestFactory

/// @notice Factory for creating contests and managing their initial funding

/// @dev Inherits from BaseFactory for architecture consistency

contract ContestFactory is BaseFactory {
    using SafeERC20 for IERC20;

    uint256 public defaultContestDuration = 180 days;

    /// @notice Emitted when a new contest is created

    /// @param contestId Contest identifier

    /// @param manager Contest manager address

    /// @param category Contest category

    /// @param metadata Contest metadata

    /// @param moduleId Module identifier

    event ContestCreated(uint256 contestId, address manager, bytes32 category, bytes metadata, bytes32 moduleId);

    constructor(address core, address feeManager) BaseFactory(core, feeManager, CoreDefs.CONTEST_MODULE_ID) {}

    /// @notice Creates a new contest with specified prizes

    /// @param _prizes List of contest prizes

    /// @param /* metadata */ Unused metadata

    /// @return escrow Address of created escrow contract

    function createContest(
        PrizeInfo[] calldata _prizes,
        bytes calldata /* metadata */
    ) external payable onlyFactoryAdmin nonReentrant returns (address escrow) {
        // Check prizes array length first to save gas (cheapest check)

        uint256 prizesLen = _prizes.length;

        if (prizesLen == 0) revert InvalidPrizeData();

        // Quick basic check of first prize before expensive operations

        if (uint8(_prizes[0].prizeType) > 1) revert InvalidPrizeData(); // Check for valid prize type

        // Check for validator presence before loops

        address validator = core.getService(CoreDefs.CONTEST_MODULE_ID, 'Validator');

        // Determine which validation type to use

        if (validator != address(0)) {
            // Perform full validation through validator

            for (uint256 i = 0; i < prizesLen; i++) {
                IContestValidator(validator).validatePrize(_prizes[i]);
            }
        } else {
            // Perform basic validation if validator is not available

            for (uint256 i = 0; i < prizesLen; i++) {
                PrizeInfo calldata p = _prizes[i];

                if (p.prizeType == PrizeType.PROMO && p.token != address(0)) revert InvalidPrizeData();

                if (p.amount == 0 && p.token != address(0)) revert InvalidPrizeData();
            }
        }

        // Create ID for new contest

        bytes32 instanceId = _generateInstanceId('ContestEscrow');

        // Calculate contest deadline

        uint256 deadline = block.timestamp + defaultContestDuration;

        // instanceId is already guaranteed to be non-zero by _generateInstanceId

        uint256 gasPoolAmount = 0;

        // Gas pool functionality disabled for now

        // TODO: Implement proper gas pool with actual ERC20 token

        gasPoolAmount = 0;

        // Create escrow contract

        ContestEscrow esc = new ContestEscrow(msg.sender, _prizes, address(core), gasPoolAmount, address(0), deadline);

        escrow = address(esc);

        core.registerFeature(instanceId, escrow, 0);

        _copyServiceIfExists(instanceId, 'Validator');

        _copyServiceIfExists(instanceId, 'NFTManager');

        // Handle potential native currency (ETH) value sent with transaction

        if (msg.value > 0) {
            // Forward any ETH sent to the escrow contract

            (bool success, ) = payable(escrow).call{value: msg.value}('');

            if (!success) revert ContestFundingMissing();
        }

        // Increase maximum number of supported tokens to 20

        // ��� ��������� ����������� ����������� ������ � �������� �� DoS �� ������������ �������

        uint256 maxSupportedTokens = prizesLen < 20 ? prizesLen : 20;

        address[] memory tokens = new address[](prizesLen);

        uint256[] memory totals = new uint256[](prizesLen);

        uint256 uniqueCount = 0;

        address sender = msg.sender;

        // ������� �������������� ����� ��� ������� ����������� ERC-20 ������

        for (uint256 i = 0; i < prizesLen; i++) {
            PrizeInfo calldata p = _prizes[i];

            if (p.prizeType != PrizeType.MONETARY || p.amount == 0) continue;

            address token = p.token;

            uint256 amount = p.amount;

            if (token == address(0)) continue; // ETH �������������� ����� msg.value

            bool found = false;

            for (uint256 j = 0; j < uniqueCount; j++) {
                if (tokens[j] == token) {
                    totals[j] += amount;

                    found = true;

                    break;
                }
            }

            if (!found) {
                if (uniqueCount >= maxSupportedTokens) revert BatchTooLarge();

                tokens[uniqueCount] = token;

                totals[uniqueCount] = amount;

                uniqueCount++;
            }
        }

        for (uint256 i = 0; i < uniqueCount; i++) {
            address token = tokens[i];

            uint256 amount = totals[i];

            IERC20 tokenContract = IERC20(token);

            uint256 beforeBal = tokenContract.balanceOf(escrow);

            tokenContract.safeTransferFrom(sender, escrow, amount);

            uint256 afterBal = tokenContract.balanceOf(escrow);

            if (afterBal - beforeBal != amount) revert ContestFundingMissing();
        }

        // Emit event directly

        emit ContestCreated(
            uint256(instanceId),
            msg.sender,
            bytes32(0),
            abi.encode(_prizes),
            CoreDefs.CONTEST_MODULE_ID
        );
    }

    /// @notice Sets default contest duration

    /// @param duration Duration in seconds

    function setDefaultContestDuration(uint256 duration) external onlyFactoryAdmin {
        defaultContestDuration = duration;
    }

    /// @notice Allows contract to receive ETH (needed for native currency contests)

    receive() external payable {}

    /// @notice Fallback function that requires specific function calls

    fallback() external payable {
        revert('Use createContest');
    }
}
