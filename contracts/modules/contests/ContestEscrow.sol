// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../core/Registry.sol";
import "../../core/PaymentGateway.sol";
import "../../core/EventRouter.sol";
import "../../shared/NFTManager.sol";
import "./shared/PrizeInfo.sol";
import "./interfaces/IContestEscrow.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Ошибки для экономии газа вместо строковых require
    error ContestAlreadyFinalized();
    error WrongWinnersCount();

contract ContestEscrow is IContestEscrow, ReentrancyGuard {
    using SafeERC20 for IERC20;
    Registry    public immutable registry;
    address     public immutable creator;
    PrizeInfo[] public prizes;
    address     public commissionToken;
    uint256     public commissionFee;
    uint256     public gasPool;
    bool        public isFinalized;
    address[]   public winners;
    uint256     public processedWinners;
    uint8       public maxWinnersPerTx = 20;

    event MonetaryPrizePaid(address indexed to, uint256 amount);
    event PromoPrizeIssued(uint8 indexed slot, address indexed to, string uri);
    event PrizeAssigned(address winner, string uri);
    event PrizeAdded(uint256 indexed slot, address indexed token, uint256 amount, string uri);
    event ContestFinalized(address[] winners);
    event GasRefunded(address indexed to, uint256 amount);

    /// @dev Identifier used when interacting with registry services
    bytes32 public constant MODULE_ID = keccak256("Contest");

    modifier onlyCreator() {
        require(msg.sender == creator, "Not creator");
        _;
    }

    constructor(
        Registry    _registry,
        address     _creator,
        PrizeInfo[] memory _prizes,
        address     _commissionToken,
        uint256     _commissionFee,
        uint256     _initialGasPool,
        address[] memory /* _judges */, // unused for now
        bytes memory /* _metadata */
    ) {
        registry        = _registry;
        creator         = _creator;
        commissionToken = _commissionToken;
        commissionFee   = _commissionFee;
        gasPool         = _initialGasPool;
        for (uint i = 0; i < _prizes.length; i++) {
            prizes.push(_prizes[i]);
        }
        // store judges & metadata if needed
    }

    function addPrizes(PrizeInfo[] calldata _prizes) external onlyCreator nonReentrant {
        for (uint256 i = 0; i < _prizes.length; i++) {
            prizes.push(_prizes[i]);
            uint256 idx = prizes.length - 1;
            if (_prizes[i].amount > 0) {
                IERC20(_prizes[i].token).safeTransferFrom(msg.sender, address(this), _prizes[i].amount);
            }
            emit PrizeAdded(idx, _prizes[i].token, _prizes[i].amount, _prizes[i].uri);
        }
    }

    function finalize(address[] calldata _winners)
    external
    nonReentrant
    onlyCreator
    {
        if (_winners.length != prizes.length) revert WrongWinnersCount();

        if (winners.length == 0) {
            winners = _winners;
        }

        uint256 gasStart = gasleft();

        uint256 start = processedWinners;
        uint256 end = start + maxWinnersPerTx;
        if (end > prizes.length) end = prizes.length;

        for (uint8 i = uint8(start); i < end; i++) {
            PrizeInfo memory p = prizes[i];
            if (p.amount > 0) {
                uint256 amount = p.distribution == 0
                    ? p.amount
                    : _computeDescending(p.amount, i);
                IERC20(p.token).safeTransfer(winners[i], amount);
                emit MonetaryPrizePaid(winners[i], amount);
            } else {
                emit PromoPrizeIssued(i, winners[i], p.uri);
                emit PrizeAssigned(winners[i], p.uri);
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

        if (processedWinners == prizes.length && !isFinalized) {
            isFinalized = true;

            // уведомляем остальные модули
            EventRouter(
                registry.getModuleService(MODULE_ID, keccak256(bytes("EventRouter")))
            ).route(
                keccak256("ContestFinalized"),
                abi.encode(creator, winners, prizes)
            );

            // чеканим бейджи
            string[] memory uris = new string[](winners.length);
            NFTManager(
                registry.getModuleService(MODULE_ID, keccak256(bytes("NFTManager")))
            ).mintBatch(winners, uris, false);

            emit ContestFinalized(winners);
        }
    }

    function _computeDescending(uint256 amount, uint8 idx)
    internal
    view
    returns (uint256)
    {
        uint256 n = prizes.length;
        uint256 rankWeight = n - idx;
        uint256 sumWeights = (n * (n + 1)) / 2;
        return (amount * rankWeight) / sumWeights;
    }
}
