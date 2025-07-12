// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../interfaces/IPaymentProcessor.sol';
import '../interfaces/IProcessorRegistry.sol';
import '../PaymentContext.sol';
import '@openzeppelin/contracts/access/AccessControl.sol';

/// @title PaymentOrchestrator
/// @notice Управляет цепочкой процессоров и обработкой платежей
contract PaymentOrchestrator is AccessControl {
    bytes32 public constant PROCESSOR_MANAGER_ROLE = keccak256('PROCESSOR_MANAGER_ROLE');

    IProcessorRegistry public processorRegistry;

    mapping(bytes32 => address[]) private moduleProcessors;
    mapping(bytes32 => mapping(string => bool)) private moduleProcessorConfig;

    event ProcessorConfigured(bytes32 indexed moduleId, string processorName, bool enabled);

    constructor(address _processorRegistry) {
        require(_processorRegistry != address(0), 'Orchestrator: zero registry address');
        processorRegistry = IProcessorRegistry(_processorRegistry);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PROCESSOR_MANAGER_ROLE, msg.sender);
    }

    function processPayment(
        bytes32 moduleId,
        address token,
        address payer,
        uint256 amount,
        bytes calldata signature
    ) external returns (uint256 netAmount, bytes32 paymentId, address feeRecipient, uint256 feeAmount) {
        PaymentContext.Context memory context = PaymentContext.createContext(
            moduleId,
            payer,
            address(0),
            token,
            amount,
            ''
        );

        bytes memory contextBytes = abi.encode(context);

        address[] memory processors = moduleProcessors[moduleId];

        for (uint256 i = 0; i < processors.length; i++) {
            address processor = processors[i];
            if (processor == address(0)) continue;

            string memory processorName = IPaymentProcessor(processor).getName();
            if (!moduleProcessorConfig[moduleId][processorName]) continue;

            if (!IPaymentProcessor(processor).isApplicable(contextBytes)) continue;

            (IPaymentProcessor.ProcessResult result, bytes memory updatedContext) = IPaymentProcessor(processor)
                .process(contextBytes);

            if (result == IPaymentProcessor.ProcessResult.FAILED) {
                context = abi.decode(updatedContext, (PaymentContext.Context));
                revert(context.errorMessage);
            }

            contextBytes = updatedContext;
        }

        context = abi.decode(contextBytes, (PaymentContext.Context));

        require(context.success, 'Payment failed');

        netAmount = context.processedAmount;
        paymentId = context.paymentId;
        feeAmount = 0; // For now, feeRecipient and feeAmount can be set by processors in context.metadata or extended later
        feeRecipient = address(0);
    }

    function convertAmount(
        bytes32 moduleId,
        address fromToken,
        address toToken,
        uint256 amount
    ) external view returns (uint256 convertedAmount) {
        address[] memory processors = moduleProcessors[moduleId];
        for (uint256 i = 0; i < processors.length; i++) {
            address processor = processors[i];
            if (processor == address(0)) continue;
            try IPaymentProcessor(processor).getName() returns (string memory name) {
                if (keccak256(abi.encodePacked(name)) == keccak256(abi.encodePacked('PriceOracle'))) {
                    try IPaymentProcessor(processor).convertAmount(moduleId, fromToken, toToken, amount) returns (
                        uint256 result
                    ) {
                        return result;
                    } catch {}
                }
            } catch {}
        }
        return amount;
    }

    function isPairSupported(
        bytes32 moduleId,
        address fromToken,
        address toToken
    ) external view returns (bool isSupported) {
        address tokenFilter = processorRegistry.getProcessorByName('TokenFilter');
        if (tokenFilter != address(0)) {
            try IPaymentProcessor(tokenFilter).isPairSupported(moduleId, fromToken, toToken) returns (bool result) {
                return result;
            } catch {}
        }
        return true;
    }

    function getProcessors(bytes32 moduleId) external view returns (address[] memory processors) {
        return moduleProcessors[moduleId];
    }

    function configureProcessor(
        bytes32 moduleId,
        string calldata processorName,
        bool enabled,
        bytes calldata configData
    ) external onlyRole(PROCESSOR_MANAGER_ROLE) returns (bool success) {
        address processor = processorRegistry.getProcessorByName(processorName);
        require(processor != address(0), 'Processor not found');

        moduleProcessorConfig[moduleId][processorName] = enabled;

        address[] storage processors = moduleProcessors[moduleId];
        bool found = false;
        for (uint256 i = 0; i < processors.length; i++) {
            if (processors[i] == processor) {
                found = true;
                break;
            }
        }
        if (!found) {
            processors.push(processor);
        }

        if (configData.length > 0) {
            IPaymentProcessor(processor).configure(moduleId, configData);
        }

        emit ProcessorConfigured(moduleId, processorName, enabled);
        return true;
    }
}
