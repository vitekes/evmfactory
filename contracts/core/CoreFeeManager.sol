// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccessControlCenter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

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
        require(access.hasRole(access.FEATURE_OWNER_ROLE(), msg.sender), "not feature owner");
        _;
    }

    modifier onlyAdmin() {
        require(access.hasRole(access.DEFAULT_ADMIN_ROLE(), msg.sender), "not admin");
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

        require(pFee <= 10_000, "fee too high");
        feeAmount = fFee + ((amount * pFee) / 10_000);
        require(feeAmount < amount, "fee >= amount");
        if (feeAmount > 0) {
            IERC20(token).safeTransferFrom(payer, address(this), feeAmount);

            collectedFees[moduleId][token] += feeAmount;
            emit FeeCollected(moduleId, token, feeAmount);
        }
    }

    function withdrawFees(bytes32 moduleId, address token, address to) external onlyAdmin nonReentrant whenNotPaused {
        uint256 amount = collectedFees[moduleId][token];
        require(amount > 0, "nothing to withdraw");

        collectedFees[moduleId][token] = 0;
        IERC20(token).safeTransfer(to, amount);

        emit FeeWithdrawn(moduleId, token, to, amount);
    }

    function setPercentFee(bytes32 moduleId, address token, uint16 feeBps) external onlyFeatureOwner {
        require(feeBps <= 10_000, "fee too high");
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
        require(newImplementation != address(0), "invalid implementation");
    }

    uint256[50] private __gap;
}
