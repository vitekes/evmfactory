// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccessControlCenter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../errors/Errors.sol";

contract CoreFeeManager is Initializable, ReentrancyGuardUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    using Address for address payable;
    using SafeERC20 for IERC20;

    AccessControlCenter public access;

    /// @notice moduleId => token => fee % (в 10000 базисных точках: 100 = 1%)
    mapping(bytes32 => mapping(address => uint16)) public percentFee;

    /// @notice moduleId => token => фиксированная плата (в токенах)
    mapping(bytes32 => mapping(address => uint256)) public fixedFee;

    /// @notice moduleId => токен => собранная сумма
    mapping(bytes32 => mapping(address => uint256)) public collectedFees;

    /// @notice moduleId => адрес => без комиссии?
    mapping(bytes32 => mapping(address => bool)) public isZeroFeeAddress;

    event FeeCollected(bytes32 indexed moduleId, address indexed token, uint256 amount);
    event FeeWithdrawn(bytes32 indexed moduleId, address indexed token, address to, uint256 amount);

    modifier onlyFeatureOwner() {
        if (!access.hasRole(access.FEATURE_OWNER_ROLE(), msg.sender)) revert NotFeatureOwner();
        _;
    }

    modifier onlyAdmin() {
        if (!access.hasRole(access.DEFAULT_ADMIN_ROLE(), msg.sender)) revert NotAdmin();
        _;
    }

    function initialize(address accessControl) public initializer {
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        access = AccessControlCenter(accessControl);
    }

    function collect(bytes32 moduleId, address token, address payer, uint256 amount) external onlyFeatureOwner nonReentrant whenNotPaused returns (uint256 feeAmount) {
        if (isZeroFeeAddress[moduleId][payer]) return 0;

        uint16 pFee = percentFee[moduleId][token];
        uint256 fFee = fixedFee[moduleId][token];

        if (pFee > 10_000) revert FeeTooHigh();
        feeAmount = fFee + ((amount * pFee) / 10_000);
        if (feeAmount >= amount) revert FeeExceedsAmount();
        if (feeAmount > 0) {
            IERC20(token).safeTransferFrom(payer, address(this), feeAmount);

            collectedFees[moduleId][token] += feeAmount;
            emit FeeCollected(moduleId, token, feeAmount);
        }
    }

    /// @notice Deposit a specific amount of fees for a module without calculation
    function depositFee(bytes32 moduleId, address token, uint256 amount) external onlyFeatureOwner nonReentrant whenNotPaused {
        if (amount == 0) revert AmountZero();
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        collectedFees[moduleId][token] += amount;
        emit FeeCollected(moduleId, token, amount);
    }

    function withdrawFees(bytes32 moduleId, address token, address to) external onlyAdmin nonReentrant whenNotPaused {
        uint256 amount = collectedFees[moduleId][token];
        if (amount == 0) revert NothingToWithdraw();

        collectedFees[moduleId][token] = 0;
        IERC20(token).safeTransfer(to, amount);

        emit FeeWithdrawn(moduleId, token, to, amount);
    }

    function setPercentFee(bytes32 moduleId, address token, uint16 feeBps) external onlyFeatureOwner {
        if (feeBps > 10_000) revert FeeTooHigh();
        percentFee[moduleId][token] = feeBps;
    }

    function setFixedFee(bytes32 moduleId, address token, uint256 feeAmount) external onlyFeatureOwner {
        fixedFee[moduleId][token] = feeAmount;
    }

    function setZeroFeeAddress(bytes32 moduleId, address user, bool status) external onlyFeatureOwner {
        isZeroFeeAddress[moduleId][user] = status;
    }

    /// Позволяет заменить AccessControl
    function setAccessControl(address newAccess) external onlyAdmin {
        access = AccessControlCenter(newAccess);
    }

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyAdmin {
        if (newImplementation == address(0)) revert InvalidImplementation();
    }

    uint256[50] private __gap;
}
