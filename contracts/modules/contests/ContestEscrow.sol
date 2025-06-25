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

    uint8 public constant maxWinnersPerTx = 20;
    bytes32 public constant MODULE_ID = CoreDefs.CONTEST_MODULE_ID;

    event MonetaryPrizePaid(address indexed to, uint256 amount);
    event PromoPrizeIssued(uint8 indexed slot, address indexed to, string uri);
    event PrizeAssigned(address indexed to, string uri);
    event ContestFinalized(address[] winners);
    event GasRefunded(address indexed to, uint256 amount);

    modifier onlyCreator() {
        if (msg.sender != creator) revert NotCreator();
        _;
    }

    constructor(
        address _creator,
        PrizeInfo[] memory _prizes,
        address _registry,
        uint256 _gasPool,
        address _commissionToken
    ) {
        // factory should deploy the escrow, not the creator
        assert(msg.sender != _creator);
        registry = Registry(_registry);
        creator = _creator;
        commissionToken = _commissionToken;
        gasPool = _gasPool;
        for (uint256 i = 0; i < _prizes.length; i++) {
            prizes.push(_prizes[i]);
        }
    }

    function finalize(address[] calldata _winners) external nonReentrant onlyCreator {
        if (finalized) revert ContestAlreadyFinalized();
        if (_winners.length != prizes.length) revert WrongWinnersCount();

        if (winners.length == 0) {
            winners = _winners;
        }

        uint256 gasStart = gasleft();
        uint256 start = processedWinners;
        uint256 end = start + maxWinnersPerTx;
        if (end > prizes.length) end = prizes.length;

        bool willFinalize = end == prizes.length;
        if (willFinalize) {
            finalized = true;
        }

        for (uint256 i = start; i < end; ) {
            PrizeInfo memory p = prizes[i];
            if (p.prizeType == PrizeType.MONETARY) {
                uint256 amount = p.distribution == 0 ? p.amount : _computeDescending(p.amount, uint8(i));
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
        uint256 refund = gasUsed * tx.gasprice;
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

    function prizesLength() external view returns (uint256) {
        return prizes.length;
    }

    function winnersLength() external view returns (uint256) {
        return winners.length;
    }

    function _computeDescending(uint256 amount, uint8 idx) internal view returns (uint256) {
        uint256 n = prizes.length;
        uint256 rankWeight = n - idx;
        uint256 sumWeights = (n * (n + 1)) / 2;
        return (amount * rankWeight) / sumWeights;
    }
}
