// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccessControlCenter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract CoreFeeManager is ReentrancyGuard {
    using Address for address payable;

    AccessControlCenter public access;
    address public owner;

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
        require(msg.sender == owner, "not admin");
        _;
    }

    constructor(address accessControl) {
        access = AccessControlCenter(accessControl);
        owner = msg.sender;
    }

    function collect(bytes32 moduleId, address token, address payer, uint256 amount) external onlyFeatureOwner nonReentrant returns (uint256 feeAmount) {
        if (isZeroFeeAddress[moduleId][payer]) return 0;

        uint16 pFee = percentFee[moduleId][token];
        uint256 fFee = fixedFee[moduleId][token];

        feeAmount = fFee + ((amount * pFee) / 10_000);
        if (feeAmount > 0) {
            IERC20(token).transferFrom(payer, address(this), feeAmount);
            collectedFees[moduleId][token] += feeAmount;
            emit FeeCollected(moduleId, token, feeAmount);
        }
    }

    function withdrawFees(bytes32 moduleId, address token, address to) external onlyAdmin nonReentrant {
        uint256 amount = collectedFees[moduleId][token];
        require(amount > 0, "nothing to withdraw");

        collectedFees[moduleId][token] = 0;
        IERC20(token).transfer(to, amount);
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
}
