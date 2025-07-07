// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../../shared/BaseFactory.sol';
import './ContestEscrow.sol';
import './shared/PrizeInfo.sol';
import './interfaces/IContestValidator.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '../../shared/CoreDefs.sol';

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

    constructor(address registry, address feeManager) BaseFactory(registry, feeManager, CoreDefs.CONTEST_MODULE_ID) {}

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
        address validator = _copyServiceIfExists(CoreDefs.CONTEST_MODULE_ID, 'Validator');

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
        /* bytes32 instanceId = */ _generateInstanceId('ContestEscrow');

        // Calculate contest deadline
        uint256 deadline = block.timestamp + defaultContestDuration;

        // instanceId is already guaranteed to be non-zero by _generateInstanceId
        uint256 gasPoolAmount = 0;

        // Check if sender has allowed tokens for gas pool
        if (paymentGateway != address(0)) {
            uint256 gasBalance = IERC20(paymentGateway).allowance(msg.sender, address(this));
            if (gasBalance > 0) {
                IERC20(paymentGateway).safeTransferFrom(msg.sender, address(this), gasBalance);
                gasPoolAmount = gasBalance;
            }
        }

        // Create escrow contract
        ContestEscrow esc = new ContestEscrow(
            msg.sender,
            _prizes,
                address(core),
            gasPoolAmount,
            paymentGateway,
            deadline
        );
        escrow = address(esc);

        // Handle potential native currency (ETH) value sent with transaction
        if (msg.value > 0) {
            // Forward any ETH sent to the escrow contract
            (bool success, ) = payable(escrow).call{value: msg.value}('');
            if (!success) revert ContestFundingMissing();
        }

        // Increase maximum number of supported tokens to 20
        // This covers all realistic use cases but prevents DoS attacks
        uint256 maxPossibleTokens = prizesLen < 20 ? prizesLen : 20;
        address[] memory tokens = new address[](maxPossibleTokens);
        uint256[] memory totals = new uint256[](maxPossibleTokens);
        uint256 tcount = 0;
        address sender = msg.sender;

        // Check token limit
        uint256 uniqueTokensCount = 0;
        for (uint256 i = 0; i < prizesLen; i++) {
            if (_prizes[i].prizeType == PrizeType.MONETARY && _prizes[i].amount > 0 && _prizes[i].token != address(0)) {
                uniqueTokensCount++;
            }
        }

        // Prevent creating contest with too many unique tokens
        if (uniqueTokensCount > maxPossibleTokens) revert BatchTooLarge();

        // First pass - calculate total amounts for each token with optimized search
        for (uint256 i = 0; i < prizesLen; i++) {
            PrizeInfo calldata p = _prizes[i];
            // Use calldata instead of memory for parameter
            if (p.prizeType != PrizeType.MONETARY || p.amount == 0) continue;

            // Cache token to avoid multiple calldata access
            address token = p.token;
            uint256 amount = p.amount;

            // Fast search with optimized loop
            bool found = false;
            for (uint256 j = 0; j < tcount; j++) {
                if (tokens[j] == token) {
                    totals[j] += amount;
                    found = true;
                    break;
                }
            }
            if (!found && tcount < maxPossibleTokens) {
                tokens[tcount] = token;
                totals[tcount] = amount;
                tcount++;
            }
        }

        // Transfer tokens in one transaction for each unique token
        // with caching of token contracts and parameters
        for (uint256 i = 0; i < tcount; i++) {
            address token = tokens[i];
            uint256 amount = totals[i];
            IERC20 tokenContract = IERC20(token);

            uint256 beforeBal = tokenContract.balanceOf(escrow);
            tokenContract.safeTransferFrom(sender, escrow, amount);
            uint256 afterBal = tokenContract.balanceOf(escrow);

            if (afterBal - beforeBal != amount) revert ContestFundingMissing();
        }

        // Emit event directly
        emit ContestCreated(tcount, msg.sender, bytes32(0), abi.encode(_prizes), CoreDefs.CONTEST_MODULE_ID);
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
