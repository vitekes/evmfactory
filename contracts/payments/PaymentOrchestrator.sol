// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./interfaces/IProcessorRegistry.sol";
import "./interfaces/IPaymentProcessor.sol";
import "./PaymentContextLibrary.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title PaymentOrchestrator
/// @notice Отвечает за построение контекста и последовательный вызов процессоров
contract PaymentOrchestrator is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using PaymentContextLibrary for PaymentContextLibrary.PaymentContext;

    bytes32 public constant PROCESSOR_MANAGER_ROLE = keccak256("PROCESSOR_MANAGER_ROLE");

    address public immutable processorRegistry;

    mapping(bytes32 => address[]) public moduleProcessors;
    mapping(bytes32 => mapping(string => bool)) public moduleProcessorConfig;

    event ProcessorAdded(address indexed processor, uint256 position);
    event ProcessorConfigured(bytes32 indexed moduleId, string processorName, bool enabled);

    constructor(address _processorRegistry) {
        require(_processorRegistry != address(0), "PaymentOrchestrator: processor registry is zero address");
        processorRegistry = _processorRegistry;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PROCESSOR_MANAGER_ROLE, msg.sender);
    }

    function processPayment(
        bytes32 moduleId,
        address token,
        address payer,
        uint256 amount,
        bytes memory signature
    ) external nonReentrant returns (uint256 netAmount, bytes32 paymentId, address feeRecipient, uint256 feeAmount) {
        PaymentContextLibrary.PaymentContext memory context = PaymentContextLibrary.createContext(
            moduleId,
            payer,
            address(0),
            token,
            amount,
            PaymentContextLibrary.PaymentOperation.PAYMENT,
            signature.length > 0 ? signature : new bytes(0)
        );
        return _processPaymentThroughProcessors(context);
    }

    function _processPaymentThroughProcessors(
        PaymentContextLibrary.PaymentContext memory context
    ) internal returns (uint256 netAmount, bytes32 paymentId, address feeRecipient, uint256 feeAmount) {
        bytes32 moduleId = context.packed.moduleId;
        address token = context.packed.token;
        uint256 amount = context.packed.originalAmount;

        address[] memory processors = moduleProcessors[moduleId];
        bytes memory contextBytes = abi.encode(context);

        for (uint256 i = 0; i < processors.length; i++) {
            address processor = processors[i];
            if (processor == address(0)) continue;

            string memory processorName = IPaymentProcessor(processor).getName();
            if (!moduleProcessorConfig[moduleId][processorName]) continue;

            if (!IPaymentProcessor(processor).isApplicable(contextBytes)) continue;

            (IPaymentProcessor.ProcessResult result, bytes memory updatedContext) = IPaymentProcessor(processor).process(contextBytes);

            if (result == IPaymentProcessor.ProcessResult.FAILED) {
                context = abi.decode(updatedContext, (PaymentContextLibrary.PaymentContext));
                revert(context.results.errorMessage);
            }

            contextBytes = updatedContext;
        }

        context = abi.decode(contextBytes, (PaymentContextLibrary.PaymentContext));

        if (!context.packed.success) {
            revert(context.results.errorMessage);
        }

        netAmount = amount - context.results.feeAmount;
        paymentId = context.results.paymentId;
        feeAmount = context.results.feeAmount;
        feeRecipient = context.packed.recipient;
    }

    function convertAmount(bytes32 moduleId, address fromToken, address toToken, uint256 amount) external view returns (uint256 convertedAmount) {
        address[] memory processors = moduleProcessors[moduleId];
        for (uint256 i = 0; i < processors.length; i++) {
            address processor = processors[i];
            if (processor == address(0)) continue;
            try IPaymentProcessor(processor).getName() returns (string memory name) {
                if (keccak256(abi.encodePacked(name)) == keccak256(abi.encodePacked("OracleProcessor"))) {
                    try IPaymentProcessor(processor).convertAmount(moduleId, fromToken, toToken, amount) returns (uint256 result) {
                        return result;
                    } catch {}
                }
            } catch {}
        }
        return amount;
    }

    function isPairSupported(bytes32 moduleId, address fromToken, address toToken) external view returns (bool isSupported) {
        try IProcessorRegistry(processorRegistry).getProcessorByName("TokenFilter") returns (address tokenFilter) {
            if (tokenFilter != address(0)) {
                try IPaymentProcessor(tokenFilter).isPairSupported(moduleId, fromToken, toToken) returns (bool result) {
                    return result;
                } catch {}
            }
        } catch {}
        return true;
    }

    function getSupportedTokens(bytes32 moduleId) external view returns (address[] memory tokens) {
        try IProcessorRegistry(processorRegistry).getProcessorByName("TokenFilter") returns (address tokenFilter) {
            if (tokenFilter != address(0)) {
                try IPaymentProcessor(tokenFilter).getAllowedTokens(moduleId) returns (address[] memory result) {
                    return result;
                } catch {}
            }
        } catch {}
        address[] memory defaultTokens = new address[](1);
        defaultTokens[0] = address(0);
        return defaultTokens;
    }

    function addProcessor(address processor, uint256 position) external onlyRole(PROCESSOR_MANAGER_ROLE) returns (bool success) {
        require(processor != address(0), "PaymentOrchestrator: processor is zero address");
        require(IPaymentProcessor(processor).getVersion().length > 0, "PaymentOrchestrator: invalid processor");
        IProcessorRegistry registry = IProcessorRegistry(processorRegistry);
        string memory processorName = IPaymentProcessor(processor).getName();
        if (registry.getProcessorByName(processorName) == address(0)) {
            registry.registerProcessor(processor, position);
        }
        emit ProcessorAdded(processor, position);
        return true;
    }

    function configureProcessor(bytes32 moduleId, string memory processorName, bool enabled, bytes memory configData) external onlyRole(PROCESSOR_MANAGER_ROLE) returns (bool success) {
        IProcessorRegistry registry = IProcessorRegistry(processorRegistry);
        address processor = registry.getProcessorByName(processorName);
        require(processor != address(0), "PaymentOrchestrator: processor not found");
        moduleProcessorConfig[moduleId][processorName] = enabled;
        bool found = false;
        address[] storage processors = moduleProcessors[moduleId];
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

    function getProcessors(bytes32 moduleId) external view returns (address[] memory processors) {
        return moduleProcessors[moduleId];
    }

    function isEnabled(bytes32 moduleId) external view returns (bool enabled) {
        return moduleProcessors[moduleId].length > 0;
    }
}

