// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../../core/CoreSystem.sol';
import '../../core/CoreDefs.sol';
import '../../errors/Errors.sol';
import '../../lib/SignatureLib.sol';
import './interfaces/IPlanManager.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';

interface ISubscriptionDomain {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

/// @title PlanManager
/// @notice Управление тарифными планами для SubscriptionManager
contract PlanManager is IPlanManager {
    CoreSystem public immutable core;
    address public immutable subscriptionManager;
    bytes32 public immutable MODULE_ID;
    bytes32 public immutable domainSeparator;

    uint8 public maxActivePlans;

    mapping(bytes32 => PlanData) private plans;
    mapping(address => bytes32[]) private merchantPlanHistory;
    mapping(address => bytes32[]) private activePlans;
    mapping(address => mapping(bytes32 => uint256)) private activePlanIndexes; // index + 1

    event PlanCreated(
        address indexed merchant,
        bytes32 indexed planHash,
        uint256 price,
        address token,
        uint32 period,
        string uri
    );
    event PlanStatusChanged(address indexed merchant, bytes32 indexed planHash, PlanStatus status);
    event PlanFrozenToggled(address indexed operator, bytes32 indexed planHash, bool frozen);
    event PlanUriUpdated(address indexed merchant, bytes32 indexed planHash, string uri);
    event PlanOwnershipTransferred(
        address indexed operator,
        bytes32 indexed planHash,
        address indexed oldMerchant,
        address newMerchant
    );
    event MaxActivePlansUpdated(uint8 oldLimit, uint8 newLimit);

    constructor(address coreAddress, address subscriptionManagerAddress, bytes32 moduleId, uint8 initialMaxActive) {
        if (coreAddress == address(0) || subscriptionManagerAddress == address(0)) revert ZeroAddress();
        core = CoreSystem(coreAddress);
        subscriptionManager = subscriptionManagerAddress;
        MODULE_ID = moduleId;
        domainSeparator = ISubscriptionDomain(subscriptionManagerAddress).DOMAIN_SEPARATOR();
        maxActivePlans = initialMaxActive;
    }

    // ---------------------------------------------------------------------
    // External API
    // ---------------------------------------------------------------------

    function createPlan(SignatureLib.Plan calldata plan, bytes calldata sigMerchant, string calldata uri) external {
        if (plan.merchant == address(0)) revert ZeroAddress();

        bool isMerchantCall = msg.sender == plan.merchant;
        bool isOperatorCall = core.hasRole(CoreDefs.OPERATOR_ROLE, msg.sender);

        if (!isMerchantCall) {
            if (!isOperatorCall) revert UnauthorizedMerchant();
            if (sigMerchant.length == 0) revert InvalidSignature();
        }
        if (plan.price == 0 || plan.period == 0) revert InvalidParameters();

        if (plan.price > type(uint128).max || plan.period > type(uint32).max) revert InvalidParameters();

        bytes32 planHash = SignatureLib.hashPlan(plan, domainSeparator);
        if (plans[planHash].merchant != address(0)) revert PlanAlreadyExists();

        if (sigMerchant.length > 0) {
            if (ECDSA.recover(planHash, sigMerchant) != plan.merchant) revert InvalidSignature();
        }

        if (maxActivePlans > 0 && activePlans[plan.merchant].length >= maxActivePlans) revert ActivePlanLimitReached();

        PlanData memory planData = PlanData({
            hash: planHash,
            merchant: plan.merchant,
            price: uint128(plan.price),
            period: uint32(plan.period),
            token: plan.token,
            status: PlanStatus.Active,
            createdAt: uint48(block.timestamp),
            updatedAt: uint48(block.timestamp),
            uri: uri
        });

        plans[planHash] = planData;
        merchantPlanHistory[plan.merchant].push(planHash);
        _addActivePlan(plan.merchant, planHash);

        emit PlanCreated(plan.merchant, planHash, plan.price, plan.token, uint32(plan.period), uri);
        emit PlanStatusChanged(plan.merchant, planHash, PlanStatus.Active);
    }

    function deactivatePlan(bytes32 planHash) external {
        PlanData storage plan = _requirePlan(planHash);
        _requireMerchantOrOperator(plan.merchant);

        if (plan.status == PlanStatus.Inactive) revert PlanInactive();
        plan.status = PlanStatus.Inactive;
        plan.updatedAt = uint48(block.timestamp);
        _removeActivePlan(plan.merchant, planHash);

        emit PlanStatusChanged(plan.merchant, planHash, PlanStatus.Inactive);
    }

    function activatePlan(bytes32 planHash) external {
        PlanData storage plan = _requirePlan(planHash);
        bool isMerchantCall = msg.sender == plan.merchant;
        bool isOperatorCall = core.hasRole(CoreDefs.OPERATOR_ROLE, msg.sender);
        if (!isMerchantCall && !isOperatorCall) revert UnauthorizedMerchant();

        if (plan.status == PlanStatus.Frozen) revert PlanFrozen();
        if (plan.status == PlanStatus.Active) revert InvalidState();

        if (maxActivePlans > 0 && activePlans[plan.merchant].length >= maxActivePlans) revert ActivePlanLimitReached();

        plan.status = PlanStatus.Active;
        plan.updatedAt = uint48(block.timestamp);
        _addActivePlan(plan.merchant, planHash);

        emit PlanStatusChanged(plan.merchant, planHash, PlanStatus.Active);
    }

    function freezePlan(bytes32 planHash, bool frozen) external {
        PlanData storage plan = _requirePlan(planHash);
        _requireOperator();

        PlanStatus newStatus = frozen ? PlanStatus.Frozen : PlanStatus.Inactive;
        if (plan.status == newStatus) revert InvalidState();

        plan.status = newStatus;
        plan.updatedAt = uint48(block.timestamp);

        if (frozen) {
            _removeActivePlan(plan.merchant, planHash);
        } else if (newStatus == PlanStatus.Inactive) {
            _removeActivePlan(plan.merchant, planHash);
        }

        emit PlanFrozenToggled(msg.sender, planHash, frozen);
        emit PlanStatusChanged(plan.merchant, planHash, plan.status);
    }

    function updatePlanUri(bytes32 planHash, string calldata uri) external {
        PlanData storage plan = _requirePlan(planHash);
        if (msg.sender != plan.merchant) revert UnauthorizedMerchant();

        plan.uri = uri;
        plan.updatedAt = uint48(block.timestamp);

        emit PlanUriUpdated(plan.merchant, planHash, uri);
    }

    function transferPlanOwnership(bytes32 planHash, address newMerchant) external {
        if (newMerchant == address(0)) revert ZeroAddress();
        PlanData storage plan = _requirePlan(planHash);
        _requireOperator();

        address oldMerchant = plan.merchant;
        if (oldMerchant == newMerchant) revert InvalidParameters();

        plan.merchant = newMerchant;
        plan.updatedAt = uint48(block.timestamp);

        if (plan.status == PlanStatus.Active) {
            _removeActivePlan(oldMerchant, planHash);
            _addActivePlan(newMerchant, planHash);
        }

        emit PlanOwnershipTransferred(msg.sender, planHash, oldMerchant, newMerchant);
    }

    function setMaxActivePlans(uint8 newLimit) external {
        _requireGovernor();
        uint8 oldLimit = maxActivePlans;
        maxActivePlans = newLimit;
        emit MaxActivePlansUpdated(oldLimit, newLimit);
    }

    // ---------------------------------------------------------------------
    // View API
    // ---------------------------------------------------------------------

    function getPlan(bytes32 planHash) external view override returns (PlanData memory) {
        PlanData memory plan = plans[planHash];
        if (plan.merchant == address(0)) revert PlanNotFound();
        return plan;
    }

    function isPlanActive(bytes32 planHash) external view override returns (bool) {
        PlanData memory plan = plans[planHash];
        return plan.status == PlanStatus.Active;
    }

    function planStatus(bytes32 planHash) external view override returns (PlanStatus) {
        PlanData memory plan = plans[planHash];
        if (plan.merchant == address(0)) revert PlanNotFound();
        return plan.status;
    }

    function listActivePlans(address merchant) external view override returns (bytes32[] memory) {
        return activePlans[merchant];
    }

    function listMerchantPlans(address merchant) external view returns (bytes32[] memory) {
        return merchantPlanHistory[merchant];
    }

    // ---------------------------------------------------------------------
    // Internal helpers
    // ---------------------------------------------------------------------

    function _requirePlan(bytes32 planHash) internal view returns (PlanData storage) {
        PlanData storage plan = plans[planHash];
        if (plan.merchant == address(0)) revert PlanNotFound();
        return plan;
    }

    function _addActivePlan(address merchant, bytes32 planHash) internal {
        if (activePlanIndexes[merchant][planHash] != 0) return;
        activePlans[merchant].push(planHash);
        activePlanIndexes[merchant][planHash] = activePlans[merchant].length;
    }

    function _removeActivePlan(address merchant, bytes32 planHash) internal {
        uint256 index = activePlanIndexes[merchant][planHash];
        if (index == 0) return;

        bytes32[] storage plansArray = activePlans[merchant];
        uint256 lastIndex = plansArray.length - 1;
        uint256 removeIndex = index - 1;

        if (removeIndex != lastIndex) {
            bytes32 lastPlan = plansArray[lastIndex];
            plansArray[removeIndex] = lastPlan;
            activePlanIndexes[merchant][lastPlan] = removeIndex + 1;
        }

        plansArray.pop();
        activePlanIndexes[merchant][planHash] = 0;
    }

    function _requireOperator() internal view {
        if (!core.hasRole(CoreDefs.OPERATOR_ROLE, msg.sender)) revert NotOperator();
    }

    function _requireMerchantOrOperator(address merchant) internal view {
        if (msg.sender == merchant) return;
        if (core.hasRole(CoreDefs.OPERATOR_ROLE, msg.sender)) return;
        revert Forbidden();
    }

    function _requireGovernor() internal view {
        if (!core.hasRole(CoreDefs.GOVERNOR_ROLE, msg.sender)) revert NotGovernor();
    }
}
