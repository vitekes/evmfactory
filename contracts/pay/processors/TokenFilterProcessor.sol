// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../interfaces/IPaymentProcessor.sol';
import '../PaymentContext.sol';
import '@openzeppelin/contracts/access/AccessControl.sol';

/// @title TokenFilterProcessor
/// @notice Процессор для фильтрации токенов
contract TokenFilterProcessor is IPaymentProcessor, AccessControl {
    bytes32 public constant PROCESSOR_ADMIN_ROLE = keccak256('PROCESSOR_ADMIN_ROLE');

    string private constant PROCESSOR_NAME = 'TokenFilter';
    string private constant PROCESSOR_VERSION = '1.0.0';

    mapping(bytes32 => mapping(address => bool)) private allowedTokens;
    mapping(bytes32 => address[]) private tokenLists;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PROCESSOR_ADMIN_ROLE, msg.sender);
    }

    function isApplicable(bytes calldata) external pure override returns (bool applicable) {
        return true; // всегда применим
    }

    function process(
        bytes calldata contextBytes
    ) external view override returns (IPaymentProcessor.ProcessResult result, bytes memory updatedContextBytes) {
        PaymentContext.Context memory context = abi.decode(contextBytes, (PaymentContext.Context));

        if (!allowedTokens[context.moduleId][context.token]) {
            context = PaymentContext.setError(context, 'TokenFilter: token not allowed');
            return (IPaymentProcessor.ProcessResult.FAILED, abi.encode(context));
        }

        updatedContextBytes = abi.encode(context);
        return (IPaymentProcessor.ProcessResult.SUCCESS, updatedContextBytes);
    }

    function getName() external pure override returns (string memory) {
        return PROCESSOR_NAME;
    }

    function getVersion() external pure override returns (string memory) {
        return PROCESSOR_VERSION;
    }

    function configure(bytes32 moduleId, bytes calldata configData) external override onlyRole(PROCESSOR_ADMIN_ROLE) {
        require(configData.length % 20 == 0, 'TokenFilter: invalid config length');

        // Очищаем предыдущий список токенов
        delete tokenLists[moduleId];

        uint256 count = configData.length / 20;
        for (uint256 i = 0; i < count; i++) {
            address token;
            assembly {
                // Правильное извлечение адреса из calldata
                // Каждый адрес занимает 20 байт, но в памяти хранится как 32-байтное слово
                let offset := add(configData.offset, mul(i, 20))
                token := shr(96, calldataload(offset)) // Сдвигаем на 96 бит (12 байт) чтобы получить адрес
            }
            allowedTokens[moduleId][token] = true;
            tokenLists[moduleId].push(token);
        }
    }

    function isPairSupported(bytes32 moduleId, address fromToken, address toToken) external view returns (bool) {
        return allowedTokens[moduleId][fromToken] && allowedTokens[moduleId][toToken];
    }

    function getAllowedTokens(bytes32 moduleId) external view returns (address[] memory tokens) {
        return tokenLists[moduleId];
    }
}
