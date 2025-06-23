// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../../interfaces/core/IRegistry.sol';
import '../../core/Registry.sol';
import '../../core/AccessControlCenter.sol';
import '../../interfaces/core/IMultiValidator.sol';
import '../../interfaces/IGateway.sol';
import '../../interfaces/IValidator.sol';
import '../../interfaces/IPriceFeed.sol';
import './shared/PrizeInfo.sol';
import './interfaces/IPrizeManager.sol';
import './ContestEscrow.sol';
import '../../shared/BaseFactory.sol';
import '../../errors/Errors.sol';
import '../../interfaces/core/ICoreFeeManager.sol';
import '../../interfaces/IPaymentGateway.sol';
import '../../interfaces/CoreDefs.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/// @title ContestFactory
/// @notice Фабрика для создания конкурсов — по шаблону или с кастомным набором слотов

contract ContestFactory is BaseFactory {
    using SafeERC20 for IERC20;

    event ContestCreated(address indexed creator, address contest);

    IPriceFeed public priceFeed;
    /// @notice Minimum contest commission in USD
    uint256 public usdFeeMin;
    /// @notice Maximum contest commission in USD
    uint256 public usdFeeMax;

    struct ContestParams {
        address[] judges;
        bytes metadata;
        address commissionToken;
    }

    constructor(
        address _registry,
        address paymentGateway,
        address validatorLogic
    ) BaseFactory(_registry, paymentGateway, CoreDefs.CONTEST_MODULE_ID) {
        AccessControlCenter acl = AccessControlCenter(registry.getCoreService(keccak256('AccessControlCenter')));
        bytes32 salt = keccak256(abi.encodePacked('Validator', MODULE_ID, address(this)));
        address val = _clone(
            validatorLogic,
            salt,
            abi.encodeWithSelector(IMultiValidator.initialize.selector, address(acl))
        );
        registry.setModuleServiceAlias(MODULE_ID, 'Validator', val);
    }

    function createContestByTemplate(
        uint256 templateId,
        ContestParams calldata params
    ) external nonReentrant onlyFactoryAdmin {
        // Получаем шаблон
        (PrizeInfo[] memory slots, ) = IPrizeManager(registry.getCoreService(keccak256('PrizeManager'))).getTemplate(
            templateId
        );

        _deployContest(slots, params);
    }

    function createCustomContest(
        PrizeInfo[] calldata slots,
        ContestParams calldata params
    ) external nonReentrant onlyFactoryAdmin {
        _deployContest(slots, params);
    }

    function _deployContest(PrizeInfo[] memory slots, ContestParams memory params) internal {
        // 1) Валидация токенов и схемы распределения, подсчёт призового пула
        IValidator validator = IValidator(registry.getModuleService(MODULE_ID, CoreDefs.SERVICE_VALIDATOR));
        bytes32 moduleId = MODULE_ID;
        for (uint i = 0; i < slots.length; i++) {
            if (slots[i].prizeType == PrizeType.MONETARY) {
                // проверяем, что токен разрешён в этом контексте
                if (!validator.isAllowed(slots[i].token)) revert NotAllowedToken();
                // проверяем корректность схемы распределения
                if (slots[i].distribution > 1) revert InvalidDistribution();
            }
        }

        // 2) Перевод призов сразу в эскроу
        // 3) Сбор комиссии за finalize()
        uint256 tokenUsd = priceFeed.tokenPriceUsd(params.commissionToken);
        if (tokenUsd == 0) revert PriceZero();
        uint256 usdFee = (usdFeeMin + usdFeeMax) / 2;
        uint256 commissionFee = (usdFee * 1e18) / tokenUsd;
        uint256 netCommission = IGateway(registry.getModuleService(MODULE_ID, CoreDefs.SERVICE_PAYMENT_GATEWAY))
            .processPayment(moduleId, params.commissionToken, msg.sender, commissionFee, '');

        uint256 gasShare = (netCommission * 60) / 100;
        uint256 feeShare = netCommission - gasShare;

        address feeManagerAddr = IPaymentGateway(registry.getModuleService(MODULE_ID, CoreDefs.SERVICE_PAYMENT_GATEWAY))
            .feeManager();
        IERC20(params.commissionToken).forceApprove(feeManagerAddr, feeShare);
        ICoreFeeManager(feeManagerAddr).depositFee(MODULE_ID, params.commissionToken, feeShare);
        IERC20(params.commissionToken).forceApprove(feeManagerAddr, 0);

        // 4) Деплой эскроу-контракта
        ContestEscrow esc = new ContestEscrow(
            Registry(address(registry)),
            msg.sender,
            slots,
            params.commissionToken,
            commissionFee,
            gasShare,
            params.judges,
            params.metadata
        );

        for (uint256 i = 0; i < slots.length; i++) {
            if (slots[i].prizeType == PrizeType.MONETARY && slots[i].amount > 0) {
                IERC20(slots[i].token).safeTransferFrom(msg.sender, address(esc), slots[i].amount);
            }
        }

        if (gasShare > 0) {
            IERC20(params.commissionToken).safeTransfer(address(esc), gasShare);
        }

        // Grant module permissions to the new contest contract
        AccessControlCenter acl = AccessControlCenter(registry.getCoreService(keccak256('AccessControlCenter')));
        bytes32[] memory roles = new bytes32[](2);
        roles[0] = acl.MODULE_ROLE();
        roles[1] = acl.FEATURE_OWNER_ROLE();
        acl.grantMultipleRoles(address(esc), roles);

        // 5) Регистрация в реестре
        registry.registerFeature(keccak256(abi.encodePacked('Contest:', address(esc))), address(esc), 1);

        emit ContestCreated(msg.sender, address(esc));
    }

    function setPriceFeed(address newFeed) external onlyFactoryAdmin {
        priceFeed = IPriceFeed(newFeed);
    }

    function setUsdFeeBounds(uint256 minFee, uint256 maxFee) external onlyFactoryAdmin {
        if (minFee > maxFee) revert InvalidBounds();
        usdFeeMin = minFee;
        usdFeeMax = maxFee;
    }
}
