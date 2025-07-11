// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './BaseProcessor.sol';
import './PaymentContextLibrary.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

/// @title FeeProcessor
/// @notice Процессор для расчета и отчисления комиссий платежей
/// @dev Наследуется от BaseProcessor и реализует логику для работы с комиссиями
contract FeeProcessor is BaseProcessor {
    using PaymentContextLibrary for PaymentContextLibrary.PaymentContext;

    // Constants
    bytes32 public constant FEE_COLLECTOR_ROLE = keccak256('FEE_COLLECTOR_ROLE');

    // Структура для настройки комиссий модуля
    struct FeeConfig {
        uint16 feePercentage; // в базисных пунктах (1 = 0.01%)
        address feeRecipient;
        bool active;
    }

    // Конфигурации комиссий для модулей
    mapping(bytes32 => FeeConfig) public feeConfigs;

    // События
    event FeeConfigured(bytes32 indexed moduleId, uint16 feePercentage, address feeRecipient);
    event FeeCollected(bytes32 indexed moduleId, address token, uint256 amount, address recipient);

    /**
     * @dev Конструктор процессора комиссий
     */
    constructor() BaseProcessor() {
        _grantRole(FEE_COLLECTOR_ROLE, msg.sender);
    }

    /**
     * @notice Получить имя процессора
     * @return name Имя процессора
     */
    function getName() public pure override returns (string memory name) {
        return 'FeeProcessor';
    }

    /**
     * @notice Получить версию процессора
     * @return version Версия процессора
     */
    function getVersion() public pure override returns (string memory version) {
        return '1.0.0';
    }

    /**
     * @notice Настроить процессор для модуля с расширенными параметрами
     * @param moduleId Идентификатор модуля
     * @param feePercentage Процент комиссии в базисных пунктах
     * @param feeRecipient Получатель комиссии
     * @return success Успешность настройки
     */
    function configureFees(
        bytes32 moduleId,
        uint16 feePercentage,
        address feeRecipient
    ) external onlyRole(PROCESSOR_ADMIN_ROLE) returns (bool success) {
        require(feePercentage <= 10000, 'FeeProcessor: fee percentage too high');
        require(feeRecipient != address(0), 'FeeProcessor: fee recipient is zero address');

        feeConfigs[moduleId] = FeeConfig({feePercentage: feePercentage, feeRecipient: feeRecipient, active: true});

        // Активируем процессор для модуля
        moduleEnabled[moduleId] = true;

        emit FeeConfigured(moduleId, feePercentage, feeRecipient);
        emit ModuleConfigured(moduleId, true);

        return true;
    }

    /**
     * @dev Внутренняя реализация логики обработки контекста
     * @param context Контекст платежа
     * @return result Результат обработки
     * @return updatedContext Обновленный контекст в байтах
     */
    function _processInternal(
        PaymentContextLibrary.PaymentContext memory context
    ) internal override returns (ProcessResult result, bytes memory updatedContext) {
        // Проверяем конфигурацию для модуля
        FeeConfig memory config = feeConfigs[context.packed.moduleId];
        if (!config.active) {
            context = PaymentContextLibrary.addProcessorResult(context, getName(), uint8(ProcessResult.SKIPPED));
            return (ProcessResult.SKIPPED, abi.encode(context));
        }

        // Рассчитываем комиссию
        uint256 feeAmount = (uint256(context.packed.processedAmount) * config.feePercentage) / 10000;

        // Обновляем контекст
        context.results.feeAmount = uint64(feeAmount);
        context.packed.recipient = config.feeRecipient;

        // Добавляем результат обработки
        context = PaymentContextLibrary.addProcessorResult(context, getName(), uint8(ProcessResult.SUCCESS));

        emit FeeCollected(context.packed.moduleId, context.packed.token, feeAmount, config.feeRecipient);

        return (ProcessResult.SUCCESS, abi.encode(context));
    }

    /**
     * @dev Внутренняя реализация проверки применимости
     * @param context Контекст платежа
     * @return applicable Применим ли процессор
     */
    function _isApplicableInternal(
        PaymentContextLibrary.PaymentContext memory context
    ) internal view override returns (bool applicable) {
        // Процессор применим, если активен для модуля и настроена конфигурация комиссий
        FeeConfig memory config = feeConfigs[context.packed.moduleId];
        return moduleEnabled[context.packed.moduleId] && config.active && config.feePercentage > 0;
    }

    /**
     * @dev Внутренняя функция для дополнительной настройки
     * @param moduleId Идентификатор модуля
     * @param config Конфигурация
     */
    function _configureInternal(bytes32 moduleId, bytes calldata config) internal override {
        if (config.length >= 64) {
            // 32 bytes for feePercentage (uint16) + 32 bytes for feeRecipient (address)
            (uint16 feePercentage, address feeRecipient) = abi.decode(config, (uint16, address));
            if (feeRecipient != address(0)) {
                feeConfigs[moduleId] = FeeConfig({
                    feePercentage: feePercentage,
                    feeRecipient: feeRecipient,
                    active: true
                });

                emit FeeConfigured(moduleId, feePercentage, feeRecipient);
            }
        }
    }
}
