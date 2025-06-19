// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ICoreFeeManager {
    function collect(bytes32 moduleId, address token, address payer, uint256 amount) external returns (uint256 feeAmount);
    function depositFee(bytes32 moduleId, address token, uint256 amount) external;
    function withdrawFees(bytes32 moduleId, address token, address to) external;
    function setPercentFee(bytes32 moduleId, address token, uint16 feeBps) external;
    function setFixedFee(bytes32 moduleId, address token, uint256 feeAmount) external;
    function setZeroFeeAddress(bytes32 moduleId, address user, bool status) external;
    function setAccessControl(address newAccess) external;
}
