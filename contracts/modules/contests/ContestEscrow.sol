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
    bool        public isFinalized;
    address[]   public winners;
    uint256     public processedWinners;
    uint8       public maxWinnersPerTx = 20;

    event MonetaryPrizePaid(address indexed to, uint256 amount);
    event PromoPrizeIssued(uint8 indexed slot, address indexed to);
    event ContestFinalized(address[] winners);

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
        address[] memory /* _judges */, // unused for now
        bytes memory /* _metadata */
    ) {
        registry        = _registry;
        creator         = _creator;
        commissionToken = _commissionToken;
        commissionFee   = _commissionFee;
        for (uint i = 0; i < _prizes.length; i++) {
            prizes.push(_prizes[i]);
        }
        // store judges & metadata if needed
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

        uint256 start = processedWinners;
        uint256 end = start + maxWinnersPerTx;
        if (end > prizes.length) end = prizes.length;

        for (uint8 i = uint8(start); i < end; i++) {
            PrizeInfo memory p = prizes[i];
            if (p.prizeType == PrizeType.MONETARY) {
                uint256 amount = p.distribution == 0
                    ? p.amount
                    : _computeDescending(p.amount, i);
                IERC20(p.token).safeTransfer(winners[i], amount);
                emit MonetaryPrizePaid(winners[i], amount);
            } else {
                emit PromoPrizeIssued(i, winners[i]);
            }
        }

        processedWinners = end;

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
