// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../../core/Registry.sol';
import '../../core/EventRouter.sol';
import '../../shared/NFTManager.sol';
import '../../errors/Errors.sol';
import './shared/PrizeInfo.sol';
import '../../interfaces/CoreDefs.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/// @title ContestEscrow
contract ContestEscrow is ReentrancyGuard {
    using SafeERC20 for IERC20;

    Registry public immutable registry;
    address public immutable creator;
    PrizeInfo[] public prizes;
    address[] public winners;

    address public commissionToken;
    uint256 public gasPool;
    uint256 public processedWinners;
    bool public finalized;
    uint256 public deadline;
    uint256 public constant GRACE_PERIOD = 30 days;
    bytes32 public winnerCommitment;
    bool public isCommitted;

    uint8 public constant maxWinnersPerTx = 20;
    bytes32 public constant MODULE_ID = CoreDefs.CONTEST_MODULE_ID;

    event MonetaryPrizePaid(address indexed to, uint256 amount);
    event PromoPrizeIssued(uint8 indexed slot, address indexed to, string uri);
    event PrizeAssigned(address indexed to, string uri);
    event ContestFinalized(address[] winners);
    event GasRefunded(address indexed to, uint256 amount);
    event WinnersCommitted(bytes32 commitment);

    modifier onlyCreator() {
        if (msg.sender != creator) revert NotCreator();
        _;
    }

    constructor(
        address _creator,
        PrizeInfo[] memory _prizes,
        address _registry,
        uint256 _gasPool,
        address _commissionToken,
        uint256 _deadline
    ) {
        // factory should deploy the escrow, not the creator
        assert(msg.sender != _creator);
        registry = Registry(_registry);
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
    /// @param nonce Nonce used when committing winners
    function finalize(address[] calldata _winners, uint256 priorityCap, uint256 nonce)
        external
        nonReentrant
        onlyCreator
    {
        if (finalized) revert ContestAlreadyFinalized();
        if (_winners.length != prizes.length) revert WrongWinnersCount();

        // Verify commitment if it was previously set
        if (isCommitted) {
            bytes32 computedCommitment = keccak256(abi.encode(_winners, nonce));
            if (computedCommitment != winnerCommitment) revert CommitmentInvalid();
        }

        if (winners.length == 0) {
            winners = _winners;
        }

        uint256 gasStart = gasleft();
        uint256 start = processedWinners;
        uint256 end = start + maxWinnersPerTx;
        if (end > prizes.length) end = prizes.length;

        // mark as finalized before any external calls
        if (end == prizes.length) {
            finalized = true;
        }

        for (uint256 i = start; i < end; ) {
            PrizeInfo memory p = prizes[i];
            if (p.prizeType == PrizeType.MONETARY) {
                uint256 amount =
                    p.distribution == 0 ? p.amount : _computeDescending(p.amount, uint8(i));
                if (IERC20(p.token).balanceOf(address(this)) < amount) revert InsufficientBalance();
                IERC20(p.token).safeTransfer(winners[i], amount);
                emit MonetaryPrizePaid(winners[i], amount);
            } else {
                emit PromoPrizeIssued(uint8(i), winners[i], p.uri);
                emit PrizeAssigned(winners[i], p.uri);
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
            address router = registry.getModuleService(MODULE_ID, keccak256(bytes('EventRouter')));
            if (router != address(0)) {
                EventRouter(router).route(EventRouter.EventKind.ContestFinalized, abi.encode(creator, winners, prizes));
            }

            address nft = registry.getModuleService(MODULE_ID, keccak256(bytes('NFTManager')));
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
        finalized = true;
        for (uint256 i = 0; i < prizes.length; i++) {
            PrizeInfo memory p = prizes[i];
            if (p.prizeType == PrizeType.MONETARY && p.amount > 0) {
                IERC20(p.token).safeTransfer(creator, p.amount);
            }
        }
        if (gasPool > 0) {
            IERC20(commissionToken).safeTransfer(creator, gasPool);
            gasPool = 0;
        }
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

    function _computeDescending(uint256 amount, uint8 idx) internal view returns (uint256) {
        uint256 n = prizes.length;
        uint256 rankWeight = n - idx;
        uint256 sumWeights = (n * (n + 1)) / 2;
        return (amount * rankWeight) / sumWeights;
    }

    /// @notice Emergency withdrawal if the contest was not finalized in time
    function emergencyWithdraw() external onlyCreator nonReentrant {
        if (finalized) revert ContestAlreadyFinalized();
        if (block.timestamp <= deadline + GRACE_PERIOD) revert GracePeriodNotExpired();

        finalized = true;
        for (uint256 i = 0; i < prizes.length; i++) {
            PrizeInfo memory p = prizes[i];
            if (p.prizeType == PrizeType.MONETARY && p.amount > 0) {
                IERC20(p.token).safeTransfer(creator, p.amount);
            }
        }
        if (gasPool > 0) {
            IERC20(commissionToken).safeTransfer(creator, gasPool);
            gasPool = 0;
        }
    }
}
