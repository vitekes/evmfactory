// contracts/modules/contests/ContestFactory.sol
pragma solidity 0.8.28;

import "../../core/Registry.sol";
import "../../core/AccessControlCenter.sol";
import "../../core/MultiValidator.sol";
import "../../core/PaymentGateway.sol";
import "../shared/PrizeInfo.sol";
import "./interfaces/IPrizeManager.sol";
import "./ContestEscrow.sol";

/// @title ContestFactory
/// @notice Фабрика для создания конкурсов — по шаблону или с кастомным набором слотов
contract ContestFactory {
    Registry public immutable registry;
    bytes32 public constant FACTORY_ADMIN = keccak256("FACTORY_ADMIN");
    bytes32 public constant MODULE_ID = keccak256("CONTEST_MODULE");

    event ContestCreated(address indexed creator, address contest);

    struct ContestParams {
        address[] judges;
        bytes metadata;
        address commissionToken;
        uint256 commissionFee;
    }

    constructor(address _registry) {
        registry = Registry(_registry);
    }

    function createContestByTemplate(
        uint256 templateId,
        ContestParams calldata params
    ) external {
        // Проверяем роль
        AccessControlCenter acl = AccessControlCenter(
            registry.getCoreService("AccessControlCenter")
        );
        require(acl.hasRole(FACTORY_ADMIN, msg.sender), "Not FACTORY_ADMIN");

        // Получаем шаблон
        (PrizeInfo[] memory slots,) = IPrizeManager(
            registry.getCoreService("PrizeManager")
        ).getTemplate(templateId);

        _deployContest(slots, params);
    }

    function createCustomContest(
        PrizeInfo[] calldata slots,
        ContestParams calldata params
    ) external {
        AccessControlCenter acl = AccessControlCenter(
            registry.getCoreService("AccessControlCenter")
        );
        require(acl.hasRole(FACTORY_ADMIN, msg.sender), "Not FACTORY_ADMIN");

        _deployContest(slots, params);
    }

    function _deployContest(
        PrizeInfo[] memory slots,
        ContestParams memory params
    ) internal {
        // 1) Валидация токенов и схемы распределения, подсчёт призового пула
        MultiValidator validator = MultiValidator(
            registry.getModuleService(MODULE_ID, "MultiValidator")
        );
        uint256 totalMonetary;
        bytes32 moduleId = MODULE_ID;
        for (uint i = 0; i < slots.length; i++) {
            if (slots[i].prizeType == PrizeType.MONETARY) {
                // проверяем, что токен разрешён в этом контексте
                require(
                    validator.isTokenAllowed(moduleId, slots[i].token),
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
            PaymentGateway(
                registry.getModuleService(MODULE_ID, "PaymentGateway")
            ).processPayment(
            /*moduleId*/ moduleId,
                slots[0].token,
                msg.sender,
                totalMonetary
            );
        }

        // 3) Сбор комиссии за finalize()
        if (params.commissionFee > 0) {
            PaymentGateway(
                registry.getModuleService(MODULE_ID, "PaymentGateway")
            ).processPayment(
            /*moduleId*/ moduleId,
                params.commissionToken,
                msg.sender,
                params.commissionFee
            );
        }

        // 4) Деплой эскроу-контракта
        ContestEscrow esc = new ContestEscrow(
            registry,
            msg.sender,
            slots,
            params.commissionToken,
            params.commissionFee,
            params.judges,
            params.metadata
        );

        // 5) Регистрация в реестре
        registry.registerFeature(
            keccak256(abi.encodePacked("Contest:", address(esc))),
            address(esc),
            1
        );

        emit ContestCreated(msg.sender, address(esc));
    }
}
