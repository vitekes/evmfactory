// contracts/modules/contests/ContestEscrow.sol
pragma solidity 0.8.28;

import "../../core/Registry.sol";
import "../../core/PaymentGateway.sol";
import "../../core/EventRouter.sol";
import "../../shared/NFTManager.sol";
import "../shared/PrizeInfo.sol";
import "./interfaces/IContestEscrow.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Ошибки для экономии газа вместо строковых require
    error ContestAlreadyFinalized();
    error WrongWinnersCount();

contract ContestEscrow is IContestEscrow, ReentrancyGuard {
    Registry    public immutable registry;
    address     public immutable creator;
    PrizeInfo[] public prizes;
    address     public commissionToken;
    uint256     public commissionFee;
    bool        public isFinalized;
    address[]   public winners;

    event MonetaryPrizePaid(address indexed to, uint256 amount);
    event PromoPrizeIssued(uint8 indexed slot, address indexed to);
    event ContestFinalized(address[] winners);

    bytes32 public constant MODULE_ID = keccak256("CONTEST_MODULE");

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
        address[] memory _judges,
        bytes memory _metadata
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
        if (isFinalized) revert ContestAlreadyFinalized();
        if (_winners.length != prizes.length) revert WrongWinnersCount();
        isFinalized = true;
        winners = _winners;

        // 1) взимаем комиссию за on-chain действие
        if (commissionFee > 0) {
            PaymentGateway(
                registry.getModuleService(MODULE_ID, "PaymentGateway")
            ).processPayment(
                MODULE_ID,
                commissionToken,
                creator,
                commissionFee
            );
        }

        // 2) раздача призов
        for (uint8 i = 0; i < prizes.length; i++) {
            PrizeInfo memory p = prizes[i];
            if (p.prizeType == PrizeType.MONETARY) {
                uint256 amount = p.distribution == 0
                    ? p.amount
                    : _computeDescending(p.amount, i);
                IERC20(p.token).transfer(_winners[i], amount);
                emit MonetaryPrizePaid(_winners[i], amount);
            } else {
                emit PromoPrizeIssued(i, _winners[i]);
            }
        }

        // 3) уведомляем остальные модули
        EventRouter(
            registry.getModuleService(MODULE_ID, "EventRouter")
        ).route(
            keccak256("ContestFinalized"),
            abi.encode(creator, _winners, prizes)
        );

        // 4) чеканим бейджи
        NFTManager(
            registry.getModuleService(MODULE_ID, "NFTManager")
        ).mintBatch(_winners, /* badge data */);

        emit ContestFinalized(_winners);
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
