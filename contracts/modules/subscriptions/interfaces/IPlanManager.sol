// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IPlanManager {
    enum PlanStatus {
        Inactive,
        Active,
        Frozen
    }

    struct PlanData {
        bytes32 hash;
        address merchant;
        uint128 price;
        uint32 period;
        address token;
        PlanStatus status;
        uint48 createdAt;
        uint48 updatedAt;
        string uri;
    }

    function getPlan(bytes32 planHash) external view returns (PlanData memory);

    function isPlanActive(bytes32 planHash) external view returns (bool);

    function planStatus(bytes32 planHash) external view returns (PlanStatus);

    function listActivePlans(address merchant) external view returns (bytes32[] memory);
}
