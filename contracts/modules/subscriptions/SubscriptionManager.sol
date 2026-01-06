// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../../core/CoreSystem.sol';
import '../../core/CoreDefs.sol';
import '../../errors/Errors.sol';
import '../../lib/SignatureLib.sol';
import '../../pay/interfaces/IPaymentGateway.sol';
import '../../external/IPermit2.sol';
import './interfaces/IPlanManager.sol';

interface IPlanManagerCreator is IPlanManager {
    function createPlan(SignatureLib.Plan calldata plan, bytes calldata sigMerchant, string calldata uri) external;
}
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

/// @title SubscriptionManager
/// @notice Управляет мультиуровневыми подписками с поддержкой нескольких планов на автора
contract SubscriptionManager is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    CoreSystem public immutable core;
    bytes32 public immutable MODULE_ID;
    bytes32 public immutable DOMAIN_SEPARATOR;

    enum SubscriptionStatus {
        None,
        Active,
        Inactive
    }

    enum CancelReason {
        None,
        User,
        RetryFailed,
        Operator,
        Switch
    }

    enum ActivationMode {
        ImmediateCharge,
        StartNextPeriod
    }

    struct SubscriptionState {
        address merchant;
        uint40 nextChargeAt;
        uint40 retryAt;
        uint16 retryCount;
        uint40 lastChargedAt;
        SubscriptionStatus status;
        CancelReason cancelReason;
        uint40 createdAt;
    }

    mapping(address => mapping(bytes32 => SubscriptionState)) private subscriptionStates;
    mapping(address => mapping(address => bytes32)) private activePlanByMerchant;
    mapping(address => bytes32[]) private userPlans;
    mapping(address => mapping(bytes32 => uint256)) private userPlanIndex; // index + 1
    mapping(address => uint256) private nativeDeposits;

    uint16 public batchLimit;

    uint40 public constant RETRY_DELAY = 24 hours;

    uint8 private constant SKIP_REASON_NO_PLAN = 1;
    uint8 private constant SKIP_REASON_NOT_DUE = 2;
    uint8 private constant SKIP_REASON_INSUFFICIENT_NATIVE_DEPOSIT = 3;
    uint8 private constant SKIP_REASON_PLAN_INACTIVE = 4;

    event SubscriptionActivated(
        address indexed user,
        bytes32 indexed planHash,
        address indexed merchant,
        uint40 nextChargeAt
    );
    event SubscriptionSwitched(
        address indexed user,
        bytes32 indexed fromPlan,
        bytes32 indexed toPlan,
        address merchant
    );
    event SubscriptionCancelled(address indexed user, bytes32 indexed planHash, uint8 reason);
    event SubscriptionCharged(address indexed user, bytes32 indexed planHash, uint256 amount, uint40 nextChargeAt);
    event SubscriptionRetryScheduled(address indexed user, bytes32 indexed planHash, uint40 retryAt, uint16 retryCount);
    event SubscriptionFailedFinal(address indexed user, bytes32 indexed planHash, uint8 reason);
    event ManualActivation(address indexed operator, address indexed user, bytes32 indexed planHash, uint8 mode);
    event NativeDepositIncreased(address indexed user, uint256 amount, uint256 newBalance);
    event NativeDepositWithdrawn(address indexed user, uint256 amount, uint256 newBalance);
    event ChargeSkipped(address indexed user, bytes32 indexed planHash, uint8 reason);

    modifier onlyAdmin() {
        if (!core.hasRole(0x00, msg.sender)) revert NotAdmin();
        _;
    }

    modifier onlyFeatureOwner() {
        if (!core.hasRole(CoreDefs.FEATURE_OWNER_ROLE, msg.sender)) revert NotFeatureOwner();
        _;
    }

    modifier onlyOperator() {
        if (!core.hasRole(CoreDefs.OPERATOR_ROLE, msg.sender)) revert NotOperator();
        _;
    }

    modifier onlyAutomation() {
        if (!core.hasRole(CoreDefs.AUTOMATION_ROLE, msg.sender)) revert NotAutomation();
        _;
    }

    modifier onlyRole(bytes32 role) {
        if (!core.hasRole(role, msg.sender)) revert Forbidden();
        _;
    }

    constructor(address _core, address paymentGateway, bytes32 moduleId) {
        if (_core == address(0)) revert ZeroAddress();
        if (paymentGateway == address(0)) revert InvalidAddress();

        core = CoreSystem(_core);
        MODULE_ID = moduleId;

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(uint256 chainId,address verifyingContract)'),
                block.chainid,
                address(this)
            )
        );

        batchLimit = 0;
    }

    // ---------------------------------------------------------------------
    // Публичные методы планов и подписок
    // ---------------------------------------------------------------------

    function hashPlan(SignatureLib.Plan calldata plan) public view returns (bytes32) {
        return SignatureLib.hashPlan(plan, DOMAIN_SEPARATOR);
    }

    function subscribe(
        SignatureLib.Plan calldata plan,
        bytes calldata sigMerchant,
        bytes calldata permitSig
    ) external payable nonReentrant {
        _subscribe(plan, sigMerchant, permitSig, plan.token, plan.price, '');
    }

    function subscribe(
        SignatureLib.Plan calldata plan,
        bytes calldata sigMerchant,
        bytes calldata permitSig,
        string calldata planUri
    ) external payable nonReentrant {
        _subscribe(plan, sigMerchant, permitSig, plan.token, plan.price, planUri);
    }

    function subscribeWithToken(
        SignatureLib.Plan calldata plan,
        bytes calldata sigMerchant,
        bytes calldata permitSig,
        address paymentToken,
        uint256 maxPaymentAmount
    ) external nonReentrant {
        _subscribeWithToken(plan, sigMerchant, permitSig, paymentToken, maxPaymentAmount, '');
    }

    function subscribeWithToken(
        SignatureLib.Plan calldata plan,
        bytes calldata sigMerchant,
        bytes calldata permitSig,
        address paymentToken,
        uint256 maxPaymentAmount,
        string calldata planUri
    ) external nonReentrant {
        _subscribeWithToken(plan, sigMerchant, permitSig, paymentToken, maxPaymentAmount, planUri);
    }

    function unsubscribe(address merchant) external nonReentrant {
        bytes32 planHash = activePlanByMerchant[msg.sender][merchant];
        if (planHash == bytes32(0)) revert NoPlan();
        _deactivatePlan(msg.sender, planHash, CancelReason.User);

        uint256 deposit = nativeDeposits[msg.sender];
        if (deposit > 0) {
            nativeDeposits[msg.sender] = 0;
            (bool success, ) = payable(msg.sender).call{value: deposit}('');
            if (!success) revert TransferFailed();
            emit NativeDepositWithdrawn(msg.sender, deposit, 0);
        }
    }

    function forceCancel(address user, address merchant, uint8 reason) external onlyOperator nonReentrant {
        bytes32 planHash = activePlanByMerchant[user][merchant];
        if (planHash == bytes32(0)) revert NoPlan();
        CancelReason cancelReason = reason == 0 ? CancelReason.Operator : CancelReason(reason);
        _deactivatePlan(user, planHash, cancelReason);
    }

    function activateManually(address user, bytes32 planHash, ActivationMode mode) external onlyOperator nonReentrant {
        SubscriptionState storage state = subscriptionStates[user][planHash];
        if (state.merchant == address(0)) revert PlanNotFound();

        IPlanManager.PlanData memory plan = _getPlan(planHash);
        if (plan.status != IPlanManager.PlanStatus.Active) revert PlanInactive();
        if (state.status == SubscriptionStatus.Active) revert InvalidState();

        bytes32 currentPlan = activePlanByMerchant[user][plan.merchant];
        if (currentPlan != bytes32(0) && currentPlan != planHash) {
            _deactivatePlan(user, currentPlan, CancelReason.Switch);
            emit SubscriptionSwitched(user, currentPlan, planHash, plan.merchant);
        }

        state.merchant = plan.merchant;
        if (state.createdAt == 0) {
            state.createdAt = uint40(block.timestamp);
        }
        state.status = SubscriptionStatus.Active;
        state.cancelReason = CancelReason.None;
        state.retryCount = 0;
        state.retryAt = 0;
        state.lastChargedAt = uint40(block.timestamp);
        state.nextChargeAt = mode == ActivationMode.ImmediateCharge
            ? uint40(block.timestamp)
            : uint40(block.timestamp + plan.period);

        activePlanByMerchant[user][plan.merchant] = planHash;
        _ensureUserPlanListed(user, planHash);

        emit ManualActivation(msg.sender, user, planHash, uint8(mode));
        emit SubscriptionActivated(user, planHash, plan.merchant, state.nextChargeAt);
    }

    // ---------------------------------------------------------------------
    // Автосписание
    // ---------------------------------------------------------------------

    function charge(address user, bytes32 planHash) public onlyAutomation nonReentrant {
        _charge(user, planHash, true);
    }

    function charge(address user) public onlyAutomation nonReentrant {
        bytes32 planHash = _singleActivePlan(user);
        _charge(user, planHash, true);
    }

    function chargeBatch(address[] calldata users, bytes32[] calldata plans) external onlyAutomation nonReentrant {
        if (users.length != plans.length) revert LengthMismatch();
        uint256 limit = users.length;
        if (batchLimit > 0 && limit > batchLimit) {
            limit = batchLimit;
        }

        for (uint256 i = 0; i < limit; ) {
            _charge(users[i], plans[i], false);
            unchecked {
                ++i;
            }
        }
    }

    function setBatchLimit(uint16 newLimit) external onlyRole(CoreDefs.GOVERNOR_ROLE) {
        batchLimit = newLimit;
    }

    // ---------------------------------------------------------------------
    // View функции
    // ---------------------------------------------------------------------

    function getSubscription(address user, address merchant) external view returns (SubscriptionState memory) {
        bytes32 planHash = activePlanByMerchant[user][merchant];
        if (planHash == bytes32(0)) revert NoPlan();
        return subscriptionStates[user][planHash];
    }

    function getSubscriptionByPlan(address user, bytes32 planHash) external view returns (SubscriptionState memory) {
        return subscriptionStates[user][planHash];
    }

    function getActivePlan(address user, address merchant) external view returns (bytes32) {
        return activePlanByMerchant[user][merchant];
    }

    function listUserPlans(address user) external view returns (bytes32[] memory) {
        return userPlans[user];
    }

    function getNativeDeposit(address user) external view returns (uint256) {
        return nativeDeposits[user];
    }

    // ---------------------------------------------------------------------
    // Управление депозитом
    // ---------------------------------------------------------------------

    function depositNativeFunds() external payable {
        if (msg.value == 0) revert InvalidAmount();
        nativeDeposits[msg.sender] += msg.value;
        emit NativeDepositIncreased(msg.sender, msg.value, nativeDeposits[msg.sender]);
    }

    function withdrawNativeFunds(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        uint256 balance = nativeDeposits[msg.sender];
        if (amount > balance) revert InsufficientBalance();
        nativeDeposits[msg.sender] = balance - amount;
        (bool success, ) = payable(msg.sender).call{value: amount}('');
        if (!success) revert TransferFailed();
        emit NativeDepositWithdrawn(msg.sender, amount, nativeDeposits[msg.sender]);
    }

    // ---------------------------------------------------------------------
    // Внутренние функции
    // ---------------------------------------------------------------------

    function _subscribeWithToken(
        SignatureLib.Plan calldata plan,
        bytes calldata sigMerchant,
        bytes calldata permitSig,
        address paymentToken,
        uint256 maxPaymentAmount,
        string memory planUri
    ) internal {
        if (paymentToken == address(0)) revert InvalidAddress();
        if (plan.price == 0) revert InvalidAmount();
        if (plan.merchant == address(0)) revert ZeroAddress();

        if (paymentToken == plan.token) {
            _subscribe(plan, sigMerchant, permitSig, plan.token, plan.price, planUri);
            return;
        }

        address gatewayAddress = _getPaymentGateway();
        IPaymentGateway gateway = IPaymentGateway(gatewayAddress);

        if (!gateway.isPairSupported(MODULE_ID, plan.token, paymentToken)) revert UnsupportedPair();

        uint256 paymentAmount = gateway.convertAmount(MODULE_ID, plan.token, paymentToken, plan.price);
        if (paymentAmount == 0) revert InvalidPrice();

        if (maxPaymentAmount > 0 && paymentAmount > maxPaymentAmount) revert PriceExceedsMaximum();

        _subscribe(plan, sigMerchant, permitSig, paymentToken, paymentAmount, planUri);
    }

    function _subscribe(
        SignatureLib.Plan calldata plan,
        bytes calldata sigMerchant,
        bytes calldata permitSig,
        address paymentToken,
        uint256 paymentAmount,
        string memory planUri
    ) internal {
        if (paymentAmount == 0) revert InvalidAmount();
        if (plan.merchant == address(0)) revert ZeroAddress();
        if (plan.period == 0) revert InvalidParameters();

        bool isNativePayment = paymentToken == address(0);
        if (isNativePayment) {
            if (msg.value < paymentAmount) revert InsufficientBalance();
        } else if (msg.value != 0) {
            revert InvalidAmount();
        }

        if (!(plan.expiry == 0 || plan.expiry >= block.timestamp)) revert Expired();

        bool chainAllowed = false;
        uint256 chainIdsLen = plan.chainIds.length;
        for (uint256 i = 0; i < chainIdsLen; i++) {
            if (plan.chainIds[i] == block.chainid) {
                chainAllowed = true;
                break;
            }
        }
        if (!chainAllowed) revert InvalidChain();

        bytes32 planHash = hashPlan(plan);
        _ensurePlanRegistered(planHash, plan, sigMerchant, planUri);
        IPlanManager.PlanData memory storedPlan = _getPlan(planHash);

        if (storedPlan.merchant == address(0)) revert PlanNotFound();
        if (storedPlan.status != IPlanManager.PlanStatus.Active) revert PlanInactive();
        if (storedPlan.merchant != plan.merchant) revert UnauthorizedMerchant();
        if (
            storedPlan.price != uint128(plan.price) ||
            storedPlan.period != uint32(plan.period) ||
            storedPlan.token != plan.token
        ) revert InvalidParameters();

        if (sigMerchant.length > 0 && ECDSA.recover(planHash, sigMerchant) != plan.merchant) revert InvalidSignature();

        address gatewayAddress = _getPaymentGateway();
        IPaymentGateway gateway = IPaymentGateway(gatewayAddress);

        _handlePermit(permitSig, paymentToken, gatewayAddress, paymentAmount);

        uint256 netAmount;
        if (isNativePayment) {
            uint256 depositAdded = msg.value - paymentAmount;
            netAmount = gateway.processPayment{value: paymentAmount}(
                MODULE_ID,
                paymentToken,
                msg.sender,
                paymentAmount,
                ''
            );
            if (netAmount > 0) {
                (bool success, ) = payable(plan.merchant).call{value: netAmount}('');
                if (!success) revert TransferFailed();
            }
            if (depositAdded > 0) {
                nativeDeposits[msg.sender] += depositAdded;
                emit NativeDepositIncreased(msg.sender, depositAdded, nativeDeposits[msg.sender]);
            }
        } else {
            netAmount = gateway.processPayment(MODULE_ID, paymentToken, msg.sender, paymentAmount, '');
            IERC20(paymentToken).safeTransfer(plan.merchant, netAmount);
        }

        _activateSubscription(msg.sender, planHash, storedPlan);
        emit SubscriptionCharged(msg.sender, planHash, plan.price, uint40(block.timestamp + storedPlan.period));
    }

    function _activateSubscription(address user, bytes32 planHash, IPlanManager.PlanData memory plan) internal {
        bytes32 currentPlan = activePlanByMerchant[user][plan.merchant];
        if (currentPlan != bytes32(0) && currentPlan != planHash) {
            _deactivatePlan(user, currentPlan, CancelReason.Switch);
            emit SubscriptionSwitched(user, currentPlan, planHash, plan.merchant);
        }

        SubscriptionState storage state = subscriptionStates[user][planHash];
        state.merchant = plan.merchant;
        if (state.createdAt == 0) {
            state.createdAt = uint40(block.timestamp);
        }
        state.status = SubscriptionStatus.Active;
        state.cancelReason = CancelReason.None;
        state.retryCount = 0;
        state.retryAt = 0;
        state.lastChargedAt = uint40(block.timestamp);
        state.nextChargeAt = uint40(block.timestamp + plan.period);

        activePlanByMerchant[user][plan.merchant] = planHash;
        _ensureUserPlanListed(user, planHash);

        emit SubscriptionActivated(user, planHash, plan.merchant, state.nextChargeAt);
    }

    function _charge(address user, bytes32 planHash, bool strict) internal returns (bool processed) {
        SubscriptionState storage state = subscriptionStates[user][planHash];
        if (state.status != SubscriptionStatus.Active) {
            if (strict) revert NoPlan();
            emit ChargeSkipped(user, planHash, SKIP_REASON_NO_PLAN);
            return false;
        }

        IPlanManager.PlanData memory plan = _getPlan(planHash);
        if (plan.status != IPlanManager.PlanStatus.Active) {
            if (strict) revert PlanInactive();
            emit ChargeSkipped(user, planHash, SKIP_REASON_PLAN_INACTIVE);
            return false;
        }

        uint40 dueAt = state.retryAt != 0 ? state.retryAt : state.nextChargeAt;
        if (block.timestamp < dueAt) {
            if (strict) revert NotDue();
            emit ChargeSkipped(user, planHash, SKIP_REASON_NOT_DUE);
            return false;
        }

        address gatewayAddress = _getPaymentGateway();
        IPaymentGateway gateway = IPaymentGateway(gatewayAddress);

        bool isNativePlan = plan.token == address(0);
        if (isNativePlan) {
            uint256 balance = nativeDeposits[user];
            if (balance < plan.price) {
                if (strict) revert InsufficientBalance();
                emit ChargeSkipped(user, planHash, SKIP_REASON_INSUFFICIENT_NATIVE_DEPOSIT);
                return false;
            }
            nativeDeposits[user] = balance - plan.price;
        }

        uint256 netAmount;
        if (isNativePlan) {
            netAmount = gateway.processPayment{value: plan.price}(MODULE_ID, plan.token, user, plan.price, '');
            if (netAmount > 0) {
                (bool success, ) = payable(plan.merchant).call{value: netAmount}('');
                if (!success) revert TransferFailed();
            }
        } else {
            netAmount = gateway.processPayment(MODULE_ID, plan.token, user, plan.price, '');
            IERC20(plan.token).safeTransfer(plan.merchant, netAmount);
        }

        state.lastChargedAt = uint40(block.timestamp);
        state.nextChargeAt = uint40(block.timestamp + plan.period);
        state.retryAt = 0;
        state.retryCount = 0;

        emit SubscriptionCharged(user, planHash, plan.price, state.nextChargeAt);
        return true;
    }

    function markFailedCharge(address user, bytes32 planHash) external onlyAutomation {
        SubscriptionState storage state = subscriptionStates[user][planHash];
        if (state.status != SubscriptionStatus.Active) revert NoPlan();

        if (state.retryCount == 0) {
            state.retryCount = 1;
            state.retryAt = uint40(block.timestamp + RETRY_DELAY);
            emit SubscriptionRetryScheduled(user, planHash, state.retryAt, state.retryCount);
        } else {
            state.status = SubscriptionStatus.Inactive;
            state.retryAt = 0;
            state.cancelReason = CancelReason.RetryFailed;
            activePlanByMerchant[user][state.merchant] = bytes32(0);
            emit SubscriptionFailedFinal(user, planHash, uint8(CancelReason.RetryFailed));
        }
    }

    function _deactivatePlan(address user, bytes32 planHash, CancelReason reason) internal {
        SubscriptionState storage state = subscriptionStates[user][planHash];
        if (state.status != SubscriptionStatus.Active) return;

        state.status = SubscriptionStatus.Inactive;
        state.cancelReason = reason;
        state.retryAt = 0;
        state.retryCount = 0;
        activePlanByMerchant[user][state.merchant] = bytes32(0);

        emit SubscriptionCancelled(user, planHash, uint8(reason));
    }

    function _ensureUserPlanListed(address user, bytes32 planHash) internal {
        if (userPlanIndex[user][planHash] != 0) return;
        userPlans[user].push(planHash);
        userPlanIndex[user][planHash] = userPlans[user].length;
    }

    function _singleActivePlan(address user) internal view returns (bytes32 planHash) {
        bytes32[] storage plans = userPlans[user];
        bytes32 activePlan;
        uint256 activeCount;

        for (uint256 i = 0; i < plans.length; i++) {
            SubscriptionState storage state = subscriptionStates[user][plans[i]];
            if (state.status == SubscriptionStatus.Active) {
                activePlan = plans[i];
                activeCount++;
                if (activeCount > 1) {
                    revert ActivePlanExists();
                }
            }
        }

        if (activeCount == 0) revert NoPlan();
        return activePlan;
    }

    function _handlePermit(
        bytes calldata permitSig,
        address paymentToken,
        address gatewayAddress,
        uint256 paymentAmount
    ) internal {
        if (permitSig.length == 0 || paymentToken == address(0)) {
            return;
        }

        (uint256 deadline, uint8 v, bytes32 r, bytes32 s) = abi.decode(permitSig, (uint256, uint8, bytes32, bytes32));
        try IERC20Permit(paymentToken).permit(msg.sender, gatewayAddress, paymentAmount, deadline, v, r, s) {
            return;
        } catch {
            address permit2 = core.getService(MODULE_ID, 'Permit2');
            if (permit2 == address(0)) revert PermitFailed();
            bytes memory data = abi.encodeWithSelector(
                IPermit2.permitTransferFrom.selector,
                IPermit2.PermitTransferFrom({
                    permitted: IPermit2.TokenPermissions({token: paymentToken, amount: paymentAmount}),
                    nonce: 0,
                    deadline: deadline
                }),
                IPermit2.SignatureTransferDetails({to: gatewayAddress, requestedAmount: paymentAmount}),
                msg.sender,
                abi.encodePacked(r, s, v)
            );
            (bool ok, ) = permit2.call(data);
            if (!ok) revert PermitFailed();
        }
    }

    function _getPlan(bytes32 planHash) internal view returns (IPlanManager.PlanData memory) {
        address service = _getPlanManagerAddress();
        return IPlanManager(service).getPlan(planHash);
    }

    function _getPaymentGateway() internal view returns (address) {
        address gatewayAddress = core.getService(MODULE_ID, 'PaymentGateway');
        if (gatewayAddress == address(0)) revert PaymentGatewayNotRegistered();
        return gatewayAddress;
    }

    function _getPlanManagerAddress() internal view returns (address) {
        address service = core.getService(MODULE_ID, 'PlanManager');
        if (service == address(0)) revert ServiceNotFound();
        return service;
    }

    function _ensurePlanRegistered(
        bytes32 planHash,
        SignatureLib.Plan calldata plan,
        bytes calldata sigMerchant,
        string memory planUri
    ) internal {
        address planManagerAddress = _getPlanManagerAddress();

        try IPlanManager(planManagerAddress).getPlan(planHash) {
            return;
        } catch (bytes memory reason) {
            if (!_isPlanNotFound(reason)) {
                _bubbleRevert(reason);
            }
        }

        if (sigMerchant.length == 0) revert InvalidSignature();

        try IPlanManagerCreator(planManagerAddress).createPlan(plan, sigMerchant, planUri) {
            return;
        } catch (bytes memory reason) {
            if (_isPlanAlreadyExists(reason)) {
                return;
            }
            _bubbleRevert(reason);
        }
    }

    function _isPlanNotFound(bytes memory revertData) internal pure returns (bool) {
        return _matchesSelector(revertData, PlanNotFound.selector);
    }

    function _isPlanAlreadyExists(bytes memory revertData) internal pure returns (bool) {
        return _matchesSelector(revertData, PlanAlreadyExists.selector);
    }

    function _matchesSelector(bytes memory revertData, bytes4 selector) internal pure returns (bool) {
        if (revertData.length < 4) return false;
        bytes4 received;
        assembly {
            received := mload(add(revertData, 32))
        }
        return received == selector;
    }

    function _bubbleRevert(bytes memory revertData) internal pure {
        assembly {
            revert(add(revertData, 32), mload(revertData))
        }
    }

    receive() external payable {}
}
