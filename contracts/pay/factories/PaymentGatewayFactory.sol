// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../pay/interfaces/IPaymentGateway.sol";
import "../../pay/gateway/PaymentGateway.sol";
import "../../pay/orchestrator/PaymentOrchestrator.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title PaymentGatewayFactory
/// @notice Фабрика для создания и управления платёжным шлюзом и оркестратором
contract PaymentGatewayFactory is AccessControl {
    bytes32 public constant FACTORY_ADMIN_ROLE = keccak256("FACTORY_ADMIN_ROLE");

    mapping(bytes32 => address) private gateways;
    mapping(bytes32 => address) private orchestrators;

    event GatewayCreated(bytes32 indexed id, address gateway);
    event OrchestratorCreated(bytes32 indexed id, address orchestrator);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(FACTORY_ADMIN_ROLE, msg.sender);
    }

    function createComponent(bytes32 id, bytes calldata config) external onlyRole(FACTORY_ADMIN_ROLE) returns (address component) {
        require(gateways[id] == address(0), "Component already exists");

        PaymentOrchestrator orchestrator = new PaymentOrchestrator();
        PaymentGateway gateway = new PaymentGateway(address(orchestrator));

        orchestrators[id] = address(orchestrator);
        gateways[id] = address(gateway);

        emit OrchestratorCreated(id, address(orchestrator));
        emit GatewayCreated(id, address(gateway));

        return address(gateway);
    }

    function getComponent(bytes32 id) external view returns (address component) {
        return gateways[id];
    }
}
