// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../../core/Registry.sol';
import '../../interfaces/IGateway.sol';
import '../../interfaces/IPriceOracle.sol';
import '../../interfaces/IEventRouter.sol';
import '../../core/AccessControlCenter.sol';
import '../../shared/AccessManaged.sol';
import '../../interfaces/IPermit2.sol';
import '../../lib/SignatureLib.sol';
import '../../interfaces/CoreDefs.sol';
import '../../errors/Errors.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

/// @title Subscription Manager
/// @notice Handles recurring payments with off-chain plan creation using EIP-712
/// @dev Использует PaymentGateway (IGateway) для обработки платежей и конвертации токенов
contract SubscriptionManager is AccessManaged, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    /// @notice Core registry used for service discovery
    Registry public immutable registry;
    /// @notice Identifier of the module within the registry
    bytes32 public immutable MODULE_ID;

    /// @notice Subscription data for a user
    struct Subscriber {
        uint256 nextBilling; // timestamp of the next charge
        bytes32 planHash; // plan this user is subscribed to
    }

    /// @notice Registered plans by their hash
    mapping(bytes32 => SignatureLib.Plan) public plans;
    /// @notice Active subscriber info mapped by user address
    mapping(address => Subscriber) public subscribers;

    /// @notice Maximum number of users to charge in a single batch. 0 disables the limit.
    uint16 public batchLimit;

    /// @notice EIP-712 domain separator for plan signatures
    bytes32 public immutable DOMAIN_SEPARATOR;

    // События отправляются через EventRouter
    /// @notice Emitted when a user cancels their subscription
    /// @param user Subscriber address
    /// @param planHash Hash of the plan
    event Unsubscribed(address indexed user, bytes32 indexed planHash);
    /// @notice Emitted when a plan is cancelled
    /// @param user Subscriber address
    /// @param planHash Hash of the plan
    /// @param ts Timestamp of cancellation
    event PlanCancelled(address indexed user, bytes32 indexed planHash, uint256 ts);
    /// @notice Emitted after a successful recurring charge
    /// @param user Subscriber address
    /// @param planHash Hash of the plan
    /// @param amount Amount charged
    /// @param nextBilling Next timestamp for payment
    event SubscriptionCharged(address indexed user, bytes32 indexed planHash, uint256 amount, uint256 nextBilling);

    /// @notice Initializes the subscription manager and registers services
    /// @param _registry Address of the core Registry contract
    /// @param paymentGateway Address of the payment gateway implementing IGateway
    /// @param moduleId Unique module identifier
    constructor(
        address _registry,
        address paymentGateway,
        bytes32 moduleId
    ) AccessManaged(Registry(_registry).getCoreService(CoreDefs.SERVICE_ACCESS_CONTROL)) {
        // Проверка наличия платежного шлюза (проверяем только валидность адреса,
        // сам объект будет получен через registry при необходимости)
        if (paymentGateway == address(0)) revert InvalidAddress();
        registry = Registry(_registry);
        MODULE_ID = moduleId;

        // Инициализируем DOMAIN_SEPARATOR как immutable переменную
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(uint256 chainId,address verifyingContract)'),
                block.chainid,
                address(this)
            )
        );

        batchLimit = 0;
    }

    /// @notice Calculates the EIP-712 hash of a subscription plan
    /// @param plan Plan parameters
    /// @return Hash to be signed by the merchant
    function hashPlan(SignatureLib.Plan calldata plan) public view returns (bytes32) {
        return SignatureLib.hashPlan(plan, DOMAIN_SEPARATOR);
    }

    /// @notice Subscribe caller to a plan
    /// @param plan Plan parameters signed by the merchant
    /// @param sigMerchant Merchant signature over the plan
    /// @param permitSig Optional permit or Permit2 signature for token spending
    function subscribe(
        SignatureLib.Plan calldata plan,
        bytes calldata sigMerchant,
        bytes calldata permitSig
    ) external nonReentrant {
        _subscribe(plan, sigMerchant, permitSig, plan.token, plan.price);
    }

    /// @notice Subscribe caller to a plan using an alternative token
    /// @param plan Plan parameters signed by the merchant
    /// @param sigMerchant Merchant signature over the plan
    /// @param permitSig Optional permit or Permit2 signature for token spending
    /// @param paymentToken Alternative token to use for payment
    /// @param maxPaymentAmount Maximum amount to pay (0 to disable check)
    function subscribeWithToken(
        SignatureLib.Plan calldata plan,
        bytes calldata sigMerchant,
        bytes calldata permitSig,
        address paymentToken,
        uint256 maxPaymentAmount
    ) external nonReentrant {
        // Предварительные проверки (самые дешевые)
        if (paymentToken == address(0)) revert InvalidAddress();
        if (plan.price == 0) revert InvalidAmount();
        if (plan.merchant == address(0)) revert ZeroAddress();

        // Если токены совпадают, используем стандартный метод (быстрый путь)
        if (paymentToken == plan.token) {
            _subscribe(plan, sigMerchant, permitSig, plan.token, plan.price);
            return;
        }

        // Проверяем наличие шлюза до выполнения сложных операций
        address gatewayAddress = registry.getModuleService(MODULE_ID, CoreDefs.SERVICE_PAYMENT_GATEWAY);
        if (gatewayAddress == address(0)) revert PaymentGatewayNotRegistered();
        IGateway gateway = IGateway(gatewayAddress);

        // Проверяем поддержку пары токенов
        if (!gateway.isPairSupported(MODULE_ID, plan.token, paymentToken)) revert UnsupportedPair();

        // Рассчитываем сумму платежа в выбранном токене
        uint256 paymentAmount = gateway.convertAmount(MODULE_ID, plan.token, paymentToken, plan.price);
        if (paymentAmount == 0) revert InvalidPrice();

        // Проверяем, что сумма не превышает максимальную
        if (maxPaymentAmount > 0 && paymentAmount > maxPaymentAmount) {
            revert PriceExceedsMaximum();
        }

        _subscribe(plan, sigMerchant, permitSig, paymentToken, paymentAmount);
    }

    /// @notice Internal function to handle subscription logic
    /// @param plan Plan parameters signed by the merchant
    /// @param sigMerchant Merchant signature over the plan
    /// @param permitSig Optional permit or Permit2 signature for token spending
    /// @param paymentToken Token to use for payment
    /// @param paymentAmount Amount to pay in the specified token
    function _subscribe(
        SignatureLib.Plan calldata plan,
        bytes calldata sigMerchant,
        bytes calldata permitSig,
        address paymentToken,
        uint256 paymentAmount
    ) internal {
        // Сначала проверяем базовые параметры (самые дешевые проверки)
        if (paymentAmount == 0) revert InvalidAmount();
        if (paymentToken == address(0)) revert ZeroAddress();
        if (plan.merchant == address(0)) revert ZeroAddress();

        // Проверка срока действия (дешевая операция)
        if (!(plan.expiry == 0 || plan.expiry >= block.timestamp)) revert Expired();

        // Проверка поддержки цепочки (умеренно дешевая операция с циклом)
        bool chainAllowed = false;
        uint256 chainIdsLen = plan.chainIds.length;
        for (uint256 i = 0; i < chainIdsLen; i++) {
            if (plan.chainIds[i] == block.chainid) {
                chainAllowed = true;
                break;
            }
        }
        if (!chainAllowed) revert InvalidChain();

        // Проверяем наличие платежного шлюза до изменения состояния
        if (registry.getModuleServiceByAlias(MODULE_ID, 'PaymentGateway') == address(0))
            revert PaymentGatewayNotRegistered();

        // Вычисляем хэш плана перед проверкой подписи
        bytes32 planHash = hashPlan(plan);

        // Проверка подписи (самая дорогая операция) делается в последнюю очередь
        if (planHash.recover(sigMerchant) != plan.merchant) revert InvalidSignature();

        // Сохраняем план и создаем подписчика до внешних вызовов (CEI паттерн)
        if (plans[planHash].merchant == address(0)) {
            plans[planHash] = plan;
        }
        subscribers[msg.sender] = Subscriber({nextBilling: block.timestamp + plan.period, planHash: planHash});

        if (permitSig.length > 0) {
            (uint256 deadline, uint8 v, bytes32 r, bytes32 s) = abi.decode(
                permitSig,
                (uint256, uint8, bytes32, bytes32)
            );
            address paymentGateway = registry.getModuleServiceByAlias(MODULE_ID, 'PaymentGateway');
            try IERC20Permit(paymentToken).permit(msg.sender, paymentGateway, paymentAmount, deadline, v, r, s) {
                // ok
            } catch {
                address permit2 = registry.getModuleServiceByAlias(MODULE_ID, 'Permit2');
                bytes memory data = abi.encodeWithSelector(
                    IPermit2.permitTransferFrom.selector,
                    IPermit2.PermitTransferFrom({
                        permitted: IPermit2.TokenPermissions({token: paymentToken, amount: paymentAmount}),
                        nonce: 0,
                        deadline: deadline
                    }),
                    IPermit2.SignatureTransferDetails({to: paymentGateway, requestedAmount: paymentAmount}),
                    msg.sender,
                    abi.encodePacked(r, s, v)
                );
                (bool ok, ) = permit2.call(data);
                if (!ok) revert PermitFailed();
            }
        }

        // Получаем адрес шлюза для обработки платежа
        address gateway = registry.getModuleServiceByAlias(MODULE_ID, 'PaymentGateway');
        if (gateway == address(0)) revert PaymentGatewayNotRegistered();

        // Обрабатываем платеж через шлюз
        uint256 netAmount = IGateway(gateway).processPayment(MODULE_ID, paymentToken, msg.sender, paymentAmount, '');

        // Переводим средства продавцу
        IERC20(paymentToken).safeTransfer(plan.merchant, netAmount);

        // Отправляем событие через EventRouter
        // В данном случае отсутствует локальное событие, поэтому никакие дополнительные действия не требуются
        address router = registry.getModuleServiceByAlias(MODULE_ID, 'EventRouter');
        if (router != address(0)) {
            bytes memory eventData = abi.encode(
                msg.sender, // Подписчик
                plan.merchant, // Продавец
                planHash, // Хеш плана
                paymentToken, // Токен оплаты
                paymentAmount, // Сумма платежа
                plan.period, // Период подписки
                block.timestamp + plan.period // Следующее списание
            );
            IEventRouter(router).route(IEventRouter.EventKind.SubscriptionCreated, eventData);
        }
    }

    /// @dev Restricts calls to automation addresses configured in ACL
    modifier onlyAutomation() {
        AccessControlCenter acl = AccessControlCenter(registry.getCoreService(CoreDefs.SERVICE_ACCESS_CONTROL));
        if (!acl.hasRole(acl.AUTOMATION_ROLE(), msg.sender)) revert NotAutomation();
        _;
    }

    /// @notice Charge a user according to their plan
    /// @param user Address of the subscriber to charge
    function charge(address user) public onlyAutomation nonReentrant {
        _charge(user);
    }

    function _charge(address user) internal {
        Subscriber storage s = subscribers[user];
        SignatureLib.Plan memory plan = plans[s.planHash];
        if (plan.merchant == address(0)) revert NoPlan();
        if (block.timestamp < s.nextBilling) revert NotDue();

        // Обновляем состояние перед внешним вызовом (CEI паттерн)
        uint256 nextBillingTime = s.nextBilling + plan.period;
        s.nextBilling = nextBillingTime;

        // Отправляем событие через EventRouter или локальное событие, если роутер недоступен
        address router = registry.getModuleServiceByAlias(MODULE_ID, 'EventRouter');
        if (router != address(0)) {
            bytes memory eventData = abi.encode(
                user, // Подписчик
                plan.merchant, // Продавец
                s.planHash, // Хеш плана
                plan.token, // Токен оплаты
                plan.price, // Сумма платежа
                nextBillingTime // Следующее списание
            );
            IEventRouter(router).route(IEventRouter.EventKind.SubscriptionRenewed, eventData);
        } else {
            // Используем локальное событие только если EventRouter недоступен
            emit SubscriptionCharged(user, s.planHash, plan.price, nextBillingTime);
        }

        // Получаем адрес шлюза для обработки платежа
        address gateway = registry.getModuleServiceByAlias(MODULE_ID, 'PaymentGateway');
        if (gateway == address(0)) revert PaymentGatewayNotRegistered();

        // Обрабатываем платеж через шлюз
        uint256 netAmount = IGateway(gateway).processPayment(MODULE_ID, plan.token, user, plan.price, '');

        // Переводим средства продавцу
        IERC20(plan.token).safeTransfer(plan.merchant, netAmount);
    }

    /// @notice Charge multiple subscribers in a single transaction.
    /// @dev Processes up to `batchLimit` addresses if the provided array is
    ///      larger. Reverts with {NoPlan} or {NotDue} for each user that cannot
    ///      be charged.
    /// @param users Array of subscriber addresses to charge.
    function chargeBatch(address[] calldata users) external onlyAutomation {
        uint256 limit = users.length;
        if (batchLimit > 0 && limit > batchLimit) {
            limit = batchLimit;
        }
        uint256 len = limit;
        for (uint256 i = 0; i < len; ) {
            _charge(users[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Sets the maximum batch charge limit
    /// @param newLimit New limit value (0 to disable)
    function setBatchLimit(uint16 newLimit) external onlyRole(AccessControlCenter(_ACC).GOVERNOR_ROLE()) {
        batchLimit = newLimit;
    }

    /// @notice Метод для обратной совместимости
    /// @param plan План подписки, подписанный продавцом
    /// @param sigMerchant Подпись продавца
    /// @param permitSig Опциональная подпись для разрешения на списание токенов
    /// @param paymentToken Альтернативный токен для оплаты
    function subscribeWithToken(
        SignatureLib.Plan calldata plan,
        bytes calldata sigMerchant,
        bytes calldata permitSig,
        address paymentToken
    ) external nonReentrant {
        // Вызываем новую версию с отключенной проверкой максимальной суммы
        this.subscribeWithToken(plan, sigMerchant, permitSig, paymentToken, 0);
    }

    /// @notice Получает сумму платежа для плана в указанном токене
    /// @dev Использует PaymentGateway для конвертации валюты
    /// @param plan План для расчета платежа
    /// @param paymentToken Токен для оплаты
    /// @return paymentAmount Сумма платежа в указанном токене
    function getPlanPaymentInToken(
        SignatureLib.Plan calldata plan,
        address paymentToken
    ) external view returns (uint256 paymentAmount) {
        if (paymentToken == address(0)) revert InvalidAddress();
        if (paymentToken == plan.token) {
            return plan.price;
        }

        // Используем PaymentGateway для конвертации сумм
        address gatewayAddress = registry.getModuleServiceByAlias(MODULE_ID, 'PaymentGateway');
        if (gatewayAddress == address(0)) revert PaymentGatewayNotRegistered();

        IGateway paymentGateway = IGateway(gatewayAddress);

        // Проверяем поддержку пары токенов
        if (!paymentGateway.isPairSupported(MODULE_ID, plan.token, paymentToken)) revert UnsupportedPair();

        // Конвертируем сумму
        uint256 result = paymentGateway.convertAmount(MODULE_ID, plan.token, paymentToken, plan.price);
        if (result == 0) revert InvalidPrice();
        return result;
    }

    /// @notice Cancel the caller's subscription and delete their state.
    /// @dev Emits {Unsubscribed} and {PlanCancelled}.
    function unsubscribe() external {
        Subscriber memory s = subscribers[msg.sender];
        // Проверяем, что подписка существует
        if (s.planHash == bytes32(0)) revert NoPlan();

        delete subscribers[msg.sender];

        // Отправляем событие через EventRouter или локальные события, если роутер недоступен
        address router = registry.getModuleServiceByAlias(MODULE_ID, 'EventRouter');
        if (router != address(0)) {
            bytes memory eventData = abi.encode(
                msg.sender, // Подписчик
                plans[s.planHash].merchant, // Продавец
                s.planHash, // Хеш плана
                block.timestamp // Время отмены
            );
            IEventRouter(router).route(IEventRouter.EventKind.SubscriptionCancelled, eventData);
        } else {
            // Используем локальные события только если EventRouter недоступен
            emit Unsubscribed(msg.sender, s.planHash);
            emit PlanCancelled(msg.sender, s.planHash, block.timestamp);
        }
    }
}
