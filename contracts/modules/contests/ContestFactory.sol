// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../interfaces/core/IRegistry.sol";
import "../../core/Registry.sol";
import "../../core/AccessControlCenter.sol";
import "../../interfaces/core/IMultiValidator.sol";
import "../../interfaces/IGateway.sol";
import "../../interfaces/IValidator.sol";
import "./shared/PrizeInfo.sol";
import "./interfaces/IPrizeManager.sol";
import "./ContestEscrow.sol";
import "../../shared/BaseFactory.sol";

/// @title ContestFactory
/// @notice Фабрика для создания конкурсов — по шаблону или с кастомным набором слотов

contract ContestFactory is BaseFactory {

    event ContestCreated(address indexed creator, address contest);

    struct ContestParams {
        address[] judges;
        bytes metadata;
        address commissionToken;
        uint256 commissionFee;
    }

    constructor(address _registry, address paymentGateway, address validatorLogic)
        BaseFactory(_registry, paymentGateway, keccak256("Contest"))
    {
        AccessControlCenter acl = AccessControlCenter(
            registry.getCoreService(keccak256("AccessControlCenter"))
        );
        bytes32 salt = keccak256(
            abi.encodePacked("Validator", MODULE_ID, address(this))
        );
        address val = _clone(
            validatorLogic,
            salt,
            abi.encodeWithSelector(IMultiValidator.initialize.selector, address(acl))
        );
        registry.setModuleServiceAlias(MODULE_ID, "Validator", val);
    }

    function createContestByTemplate(
        uint256 templateId,
        ContestParams calldata params
    ) external nonReentrant onlyFactoryAdmin {

        // Получаем шаблон
        (PrizeInfo[] memory slots,) = IPrizeManager(
            registry.getCoreService(keccak256("PrizeManager"))
        ).getTemplate(templateId);

        _deployContest(slots, params);
    }

    function createCustomContest(
        PrizeInfo[] calldata slots,
        ContestParams calldata params
    ) external nonReentrant onlyFactoryAdmin {

        _deployContest(slots, params);
    }

    function _deployContest(
        PrizeInfo[] memory slots,
        ContestParams memory params
    ) internal {
        // 1) Валидация токенов и схемы распределения, подсчёт призового пула
        IValidator validator = IValidator(
            registry.getModuleService(MODULE_ID, keccak256(bytes("Validator")))
        );
        uint256 totalMonetary;
        bytes32 moduleId = MODULE_ID;
        for (uint i = 0; i < slots.length; i++) {
            if (slots[i].prizeType == PrizeType.MONETARY) {
                // проверяем, что токен разрешён в этом контексте
                require(
                    validator.isAllowed(slots[i].token),
                    "Token not allowed"
                );
                // проверяем корректность схемы распределения
                require(
                    slots[i].distribution <= 1,
                    "Invalid distribution"
                );
                totalMonetary += slots[i].amount;
            }
        }

        // 2) Сбор призового пула
        if (totalMonetary > 0) {
            IGateway(
                registry.getModuleService(MODULE_ID, keccak256(bytes("PaymentGateway")))
            ).processPayment(
                moduleId,
                slots[0].token,
                msg.sender,
                totalMonetary,
                ""
            );
        }

        // 3) Сбор комиссии за finalize()
        if (params.commissionFee > 0) {
            IGateway(
                registry.getModuleService(MODULE_ID, keccak256(bytes("PaymentGateway")))
            ).processPayment(
                moduleId,
                params.commissionToken,
                msg.sender,
                params.commissionFee,
                ""
            );
        }

        // 4) Деплой эскроу-контракта
        ContestEscrow esc = new ContestEscrow(
            Registry(address(registry)),
            msg.sender,
            slots,
            params.commissionToken,
            params.commissionFee,
            params.judges,
            params.metadata
        );

        // Grant module permissions to the new contest contract
        AccessControlCenter acl = AccessControlCenter(
            registry.getCoreService(keccak256("AccessControlCenter"))
        );
        bytes32[] memory roles = new bytes32[](2);
        roles[0] = acl.MODULE_ROLE();
        roles[1] = acl.FEATURE_OWNER_ROLE();
        acl.grantMultipleRoles(address(esc), roles);

        // 5) Регистрация в реестре
        registry.registerFeature(
            keccak256(abi.encodePacked("Contest:", address(esc))),
            address(esc),
            1
        );

        emit ContestCreated(msg.sender, address(esc));
    }
}
