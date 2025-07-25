// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../../core/CoreSystem.sol';
import '../../core/NFTManager.sol';
import '../../errors/Errors.sol';
import './shared/PrizeInfo.sol';
import '../../core/CoreDefs.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/// @title ContestEscrow
contract ContestEscrow is ReentrancyGuard {
    using SafeERC20 for IERC20;

    CoreSystem public immutable core;
    address public immutable creator;
    PrizeInfo[] public prizes;
    address[] public winners;

    address public immutable commissionToken;
    uint256 public gasPool;
    uint256 public processedWinners;
    bool public finalized;
    uint256 public immutable deadline;
    uint256 public constant GRACE_PERIOD = 30 days;

    uint8 public constant maxWinnersPerTx = 20;
    bytes32 public constant MODULE_ID = CoreDefs.CONTEST_MODULE_ID;

    event MonetaryPrizePaid(address indexed to, uint256 amount);
    event PromoPrizeIssued(uint8 indexed slot, address indexed to, string uri);
    event EmergencyWithdraw(address indexed creator, uint256 timestamp);
    event ContestCancelled(address indexed creator, uint256 timestamp);
    event ContestFinalized(address[] winners);
    event GasRefunded(address indexed to, uint256 amount);

    modifier onlyCreator() {
        if (msg.sender != creator) revert NotCreator();
        _;
    }

    constructor(
        address _creator,
        PrizeInfo[] memory _prizes,
        address _coreSystem,
        uint256 _gasPool,
        address _commissionToken,
        uint256 _deadline
    ) {
        // factory should deploy the escrow, not the creator
        // Note: msg.sender should be the factory, _creator should be the contest creator
        if (_coreSystem == address(0)) revert ZeroAddress();
        // _commissionToken can be zero address if no commission token is used
        core = CoreSystem(_coreSystem);
        creator = _creator;
        commissionToken = _commissionToken;
        gasPool = _gasPool;
        deadline = _deadline > 0 ? _deadline : block.timestamp + 180 days;
        for (uint256 i = 0; i < _prizes.length; i++) {
            prizes.push(_prizes[i]);
        }
    }

    /// @notice Finalize contest and distribute prizes
    /// @param _winners List of winner addresses
    /// @param priorityCap Priority fee cap for gas refund calculation
    function finalize(address[] calldata _winners, uint256 priorityCap) external nonReentrant onlyCreator {
        if (finalized) revert ContestAlreadyFinalized();
        if (_winners.length != prizes.length) revert WrongWinnersCount();

        if (winners.length == 0) {
            // Store winners on first call
            winners = _winners;
        } else {
            // Ensure winners array is not changed on subsequent calls
            for (uint256 i = 0; i < winners.length && i < _winners.length; i++) {
                if (winners[i] != _winners[i]) revert InvalidParameters();
            }
        }

        uint256 gasStart = gasleft();
        uint256 start = processedWinners;
        uint256 end = start + maxWinnersPerTx;
        if (end > prizes.length) end = prizes.length;

        // finalized flag is set at the end when all prizes processed

        for (uint256 i = start; i < end; ) {
            PrizeInfo memory p = prizes[i];
            // Validate winner address
            if (winners[i] == address(0)) revert ZeroAddress();

            if (p.prizeType == PrizeType.MONETARY) {
                uint256 amount = p.distribution == 0 ? p.amount : _computeDescending(p.amount, uint8(i));

                if (p.token == address(0)) {
                    // Handle native ETH
                    if (address(this).balance < amount) revert InsufficientBalance();
                    (bool success, ) = payable(winners[i]).call{value: amount}('');
                    if (!success) revert TransferFailed();
                } else {
                    // Handle ERC20 tokens
                    if (IERC20(p.token).balanceOf(address(this)) < amount) revert InsufficientBalance();
                    IERC20(p.token).safeTransfer(winners[i], amount);
                }
                emit MonetaryPrizePaid(winners[i], amount);
            } else {
                emit PromoPrizeIssued(uint8(i), winners[i], p.uri);
            }
            unchecked {
                ++i;
            }
        }

        processedWinners = end;
        uint256 gasUsed = gasStart - gasleft();
        // Cap gas price to prevent manipulation
        uint256 maxGasPrice = block.basefee + priorityCap;
        uint256 actualGasPrice = tx.gasprice > maxGasPrice ? maxGasPrice : tx.gasprice;
        uint256 refund = gasUsed * actualGasPrice;
        if (refund > gasPool) refund = gasPool;
        if (refund > 0) {
            gasPool -= refund;
            IERC20(commissionToken).safeTransfer(msg.sender, refund);
            emit GasRefunded(msg.sender, refund);
        }

        if (processedWinners == prizes.length) {
            // Set finalized flag only after all prizes are processed
            finalized = true;

            address nft = core.getService(MODULE_ID, 'NFTManager');
            if (nft != address(0)) {
                string[] memory uris = new string[](winners.length);
                NFTManager(nft).mintBatch(winners, uris, false);
            }

            emit ContestFinalized(winners);
        }
    }

    /// @notice Cancel the contest and return all funds to the creator
    function cancel() external onlyCreator {
        if (finalized) revert ContestAlreadyFinalized();

        // Set finalized before external calls (CEI pattern)
        finalized = true;

        // Return all monetary prizes to the creator
        for (uint256 i = 0; i < prizes.length; i++) {
            PrizeInfo memory p = prizes[i];
            if (p.prizeType == PrizeType.MONETARY && p.amount > 0) {
                if (p.token == address(0)) {
                    // Handle native ETH
                    (bool success, ) = payable(creator).call{value: p.amount}('');
                    if (!success) revert TransferFailed();
                } else {
                    // Handle ERC20 tokens
                    IERC20(p.token).safeTransfer(creator, p.amount);
                }
            }
        }

        // Return remaining gas pool
        if (gasPool > 0) {
            IERC20(commissionToken).safeTransfer(creator, gasPool);
            gasPool = 0;
        }

        emit ContestCancelled(creator, block.timestamp);
    }

    /// @notice Number of prizes configured
    /// @return Length of the prizes array
    function prizesLength() external view returns (uint256) {
        return prizes.length;
    }

    /// @notice Number of winners processed
    /// @return Length of the winners array
    function winnersLength() external view returns (uint256) {
        return winners.length;
    }

    /// @notice Calculate descending prize amount
    /// @dev Amount depends on winner rank
    /// @param amount Total prize amount
    /// @param idx Winner index
    /// @return Prize amount for this winner
    function _computeDescending(uint256 amount, uint8 idx) internal view returns (uint256) {
        uint256 n = prizes.length;

        // Prevent overflow with many prizes
        if (n > type(uint128).max) revert Overflow();

        // Return zero if index exceeds number of prizes
        if (idx >= n) return 0;

        uint256 rankWeight = n - idx;
        uint256 sumWeights = (n * (n + 1)) / 2;

        // Prevent division by zero
        if (sumWeights == 0) revert InvalidDistribution();

        return (amount * rankWeight) / sumWeights;
    }

    /// @notice Emergency withdrawal if the contest was not finalized in time
    function emergencyWithdraw() external onlyCreator nonReentrant {
        if (finalized) revert ContestAlreadyFinalized();
        if (block.timestamp <= deadline + GRACE_PERIOD) revert GracePeriodNotExpired();

        // Set finalized before external calls (CEI pattern)
        finalized = true;

        // Return all monetary prizes to the creator
        for (uint256 i = 0; i < prizes.length; i++) {
            PrizeInfo memory p = prizes[i];
            if (p.prizeType == PrizeType.MONETARY && p.amount > 0) {
                if (p.token == address(0)) {
                    // Handle native ETH
                    (bool success, ) = payable(creator).call{value: p.amount}('');
                    if (!success) revert TransferFailed();
                } else {
                    // Handle ERC20 tokens
                    IERC20(p.token).safeTransfer(creator, p.amount);
                }
            }
        }

        // Return remaining gas pool
        if (gasPool > 0) {
            IERC20(commissionToken).safeTransfer(creator, gasPool);
            gasPool = 0;
        }

        // Emergency withdrawal event emitted directly

        emit EmergencyWithdraw(creator, block.timestamp);
    }

    /// @notice Allows contract to receive ETH (needed for native currency contests)
    receive() external payable {}
}
