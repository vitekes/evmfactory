// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../../core/Registry.sol';
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
        address _registry,
        uint256 _gasPool,
        address _commissionToken,
        uint256 _deadline
    ) {
        // factory should deploy the escrow, not the creator
        assert(msg.sender != _creator);
        if (_registry == address(0)) revert ZeroAddress();
        if (_commissionToken == address(0)) revert ZeroAddress();
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
    function finalize(address[] calldata _winners, uint256 priorityCap) external nonReentrant onlyCreator {
        if (finalized) revert ContestAlreadyFinalized();
        if (_winners.length != prizes.length) revert WrongWinnersCount();

        if (winners.length == 0) {
            // Сохраняем массив победителей при первом вызове
            winners = _winners;
        } else {
            // Проверка, что массив победителей не изменился при повторных вызовах
            for (uint256 i = 0; i < winners.length && i < _winners.length; i++) {
                if (winners[i] != _winners[i]) revert InvalidParameters();
            }
        }

        uint256 gasStart = gasleft();
        uint256 start = processedWinners;
        uint256 end = start + maxWinnersPerTx;
        if (end > prizes.length) end = prizes.length;

        // Флаг finalized будет установлен в конце функции, если все призы обработаны

        for (uint256 i = start; i < end; ) {
            PrizeInfo memory p = prizes[i];
            // Проверка валидности адреса победителя
            if (winners[i] == address(0)) revert ZeroAddress();

            if (p.prizeType == PrizeType.MONETARY) {
                uint256 amount = p.distribution == 0 ? p.amount : _computeDescending(p.amount, uint8(i));
                if (IERC20(p.token).balanceOf(address(this)) < amount) revert InsufficientBalance();
                IERC20(p.token).safeTransfer(winners[i], amount);
                emit MonetaryPrizePaid(winners[i], amount);
            } else {
                emit PromoPrizeIssued(uint8(i), winners[i], p.uri); // Единое событие для неденежных призов
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
            // Только сейчас устанавливаем флаг финализации, когда все призы обработаны
            finalized = true;

            // Удалено обращение к EventRouter, используем прямую эмиссию событий

            address nft = registry.getModuleService(MODULE_ID, CoreDefs.SERVICE_NFT_MANAGER);
            if (nft != address(0)) {
                string[] memory uris = new string[](winners.length);
                NFTManager(nft).mintBatch(winners, uris, false);
            }

            emit ContestFinalized(winners);
        }
    }

    /// @notice Cancel the contest and return all funds to the creator
    /// @notice Отменить конкурс и вернуть все средства создателю
    function cancel() external onlyCreator {
        if (finalized) revert ContestAlreadyFinalized();

        // Устанавливаем флаг финализации до внешних вызовов (CEI паттерн)
        finalized = true;

        // Возвращаем все денежные призы создателю
        for (uint256 i = 0; i < prizes.length; i++) {
            PrizeInfo memory p = prizes[i];
            if (p.prizeType == PrizeType.MONETARY && p.amount > 0) {
                IERC20(p.token).safeTransfer(creator, p.amount);
            }
        }

        // Возвращаем остаток пула для компенсации газа
        if (gasPool > 0) {
            IERC20(commissionToken).safeTransfer(creator, gasPool);
            gasPool = 0;
        }

        // Событие отмены эмитируется напрямую

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

    /// @notice Рассчитывает сумму приза по убывающей схеме
    /// @dev Сумма приза зависит от позиции (ранга) победителя
    /// @param amount Общая сумма приза
    /// @param idx Индекс победителя
    /// @return Расчитанная сумма приза для данного победителя
    function _computeDescending(uint256 amount, uint8 idx) internal view returns (uint256) {
        uint256 n = prizes.length;

        // Защита от переполнения при большом количестве призов
        if (n > type(uint128).max) revert Overflow();

        // Если индекс больше или равен количеству призов, возвращаем 0
        if (idx >= n) return 0;

        uint256 rankWeight = n - idx;
        uint256 sumWeights = (n * (n + 1)) / 2;

        // Защита от деления на ноль
        if (sumWeights == 0) revert InvalidDistribution();

        return (amount * rankWeight) / sumWeights;
    }

    /// @notice Аварийное изъятие средств, если конкурс не был финализирован вовремя
    function emergencyWithdraw() external onlyCreator nonReentrant {
        if (finalized) revert ContestAlreadyFinalized();
        if (block.timestamp <= deadline + GRACE_PERIOD) revert GracePeriodNotExpired();

        // Устанавливаем флаг финализации до внешних вызовов (CEI паттерн)
        finalized = true;

        // Возвращаем все денежные призы создателю
        for (uint256 i = 0; i < prizes.length; i++) {
            PrizeInfo memory p = prizes[i];
            if (p.prizeType == PrizeType.MONETARY && p.amount > 0) {
                IERC20(p.token).safeTransfer(creator, p.amount);
            }
        }

        // Возвращаем остаток пула для компенсации газа
        if (gasPool > 0) {
            IERC20(commissionToken).safeTransfer(creator, gasPool);
            gasPool = 0;
        }

        // Событие аварийного изъятия эмитируется напрямую

        emit EmergencyWithdraw(creator, block.timestamp);
    }
}
