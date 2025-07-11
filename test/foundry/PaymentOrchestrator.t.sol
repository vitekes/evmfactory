// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../contracts/payments/PaymentOrchestrator.sol";
import "../../contracts/payments/ProcessorRegistry.sol";
import "../../contracts/mocks/DummyProcessor.sol";

contract PaymentOrchestratorTest is Test {
    PaymentOrchestrator orchestrator;
    ProcessorRegistry registry;
    DummyProcessor processor;

    function setUp() public {
        registry = new ProcessorRegistry(address(1));
        orchestrator = new PaymentOrchestrator(address(registry));
        processor = new DummyProcessor();

        orchestrator.addProcessor(address(processor), 0);
        orchestrator.configureProcessor(bytes32("MODULE"), processor.getName(), true, "");
    }

    function testProcess() public {
        (uint256 netAmount, bytes32 pid, address feeRecipient, uint256 feeAmount) = orchestrator.processPayment(
            bytes32("MODULE"),
            address(0),
            address(this),
            10 ether,
            ""
        );
        assertEq(netAmount, 10 ether);
        assertEq(feeAmount, 0);
        assertEq(feeRecipient, address(0));
        assertTrue(pid != bytes32(0));
    }
}
