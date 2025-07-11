// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './interfaces/IGateway.sol';
import './PaymentOrchestrator.sol';
import '@openzeppelin/contracts/access/AccessControl.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/// @title PaymentGateway
/// @notice Платежный шлюз для маршрутизации платежей через цепочку процессоров
/// @dev Основная задача - координация обработки платежей через различные процессоры
contract PaymentGateway is IGateway, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Constants
    bytes32 public constant PAYMENT_ADMIN_ROLE = keccak256('PAYMENT_ADMIN_ROLE');
    bytes32 public constant PROCESSOR_MANAGER_ROLE = keccak256('PROCESSOR_MANAGER_ROLE');

    // Имя и версия компонента
    string private constant GATEWAY_NAME = 'PaymentGateway';
    string private constant GATEWAY_VERSION = '1.0.0';

    // State variables
    address public immutable coreSystem;
    address public immutable orchestrator;

    // Отслеживание платежей
    mapping(bytes32 => PaymentResult) public paymentResults;

    // Events
    event PaymentProcessed(
        bytes32 indexed moduleId,
        bytes32 indexed paymentId,
        address indexed token,
        address payer,
        uint256 amount,
        uint256 netAmount,
        PaymentResult result
    );

    /**
     * @dev Конструктор шлюза
     * @param _coreSystem Адрес системы ядра
     * @param _orchestrator Адрес оркестратора платежей
     */
    constructor(address _coreSystem, address _orchestrator) {
        require(_coreSystem != address(0), 'PaymentGateway: core system is zero address');
        require(_orchestrator != address(0), 'PaymentGateway: orchestrator is zero address');

        coreSystem = _coreSystem;
        orchestrator = _orchestrator;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAYMENT_ADMIN_ROLE, msg.sender);
        _grantRole(PROCESSOR_MANAGER_ROLE, msg.sender);
    }

    /**
     * @notice Обработать платеж
     * @param moduleId Идентификатор модуля
     * @param token Адрес токена (address(0) для нативной валюты)
     * @param payer Адрес плательщика
     * @param amount Сумма платежа
     * @param signature Подпись, если требуется
     * @return netAmount Чистая сумма после вычета комиссий
     */
    function processPayment(
        bytes32 moduleId,
        address token,
        address payer,
        uint256 amount,
        bytes memory signature
    ) external payable override nonReentrant returns (uint256 netAmount) {
        // Базовые проверки
        require(amount > 0, 'PaymentGateway: zero amount');

        // Проверка нативной валюты
        bool isNativeToken = token == address(0);
        if (isNativeToken) {
            require(msg.value >= amount, 'PaymentGateway: insufficient value');
        } else {
            // Перевод токенов от плательщика к шлюзу
            IERC20(token).safeTransferFrom(payer, address(this), amount);
        }

        bytes32 paymentId;
        address feeRecipient;
        uint256 feeAmount;
        (netAmount, paymentId, feeRecipient, feeAmount) = PaymentOrchestrator(orchestrator).processPayment(
            moduleId,
            token,
            payer,
            amount,
            signature
        );

        if (feeAmount > 0 && feeRecipient != address(0)) {
            if (isNativeToken) {
                payable(feeRecipient).transfer(feeAmount);
            } else {
                IERC20(token).safeTransfer(feeRecipient, feeAmount);
            }
        }

        // Сохраняем результат в истории платежей
        paymentResults[paymentId] = PaymentResult.SUCCESS;

        // Генерируем событие о успешной обработке платежа
        emit PaymentProcessed(moduleId, paymentId, token, payer, amount, netAmount, PaymentResult.SUCCESS);

        return netAmount;
    }

    /**
     * @dev Внутренний метод для обработки платежа через цепочку процессоров
     * @param context Контекст платежа
     * @param isNativeToken Флаг нативной валюты
     * @return netAmount Чистая сумма
     * @return paymentId Идентификатор платежа
     */


    /**
     * @notice Метод-делегат для конвертации суммы из одной валюты в другую
     * @dev Делегирует вызов соответствующему процессору конвертации (OracleProcessor)
     * @param moduleId Идентификатор модуля
     * @param fromToken Токен источник
     * @param toToken Токен назначения
     * @param amount Сумма для конвертации
     * @return convertedAmount Сконвертированная сумма
     */
    function convertAmount(
        bytes32 moduleId,
        address fromToken,
        address toToken,
        uint256 amount
    ) external view override returns (uint256 convertedAmount) {
        return PaymentOrchestrator(orchestrator).convertAmount(moduleId, fromToken, toToken, amount);
    }

    /**
     * @notice Делегирующий метод для проверки поддержки пары токенов
     * @dev Делегирует вызов TokenFilterProcessor
     * @param moduleId Идентификатор модуля
     * @param fromToken Токен источник
     * @param toToken Токен назначения
     * @return isSupported Поддерживается ли пара
     */
    function isPairSupported(
        bytes32 moduleId,
        address fromToken,
        address toToken
    ) external view override returns (bool isSupported) {
        return PaymentOrchestrator(orchestrator).isPairSupported(moduleId, fromToken, toToken);
    }

    /**
     * @notice Делегирующий метод для получения списка поддерживаемых токенов
     * @dev Делегирует вызов TokenFilterProcessor
     * @param moduleId Идентификатор модуля
     * @return tokens Список поддерживаемых токенов
     */
    function getSupportedTokens(bytes32 moduleId) external view override returns (address[] memory tokens) {
        return PaymentOrchestrator(orchestrator).getSupportedTokens(moduleId);
    }

    /**
     * @notice Добавить процессор в шлюз
     * @param processor Адрес процессора
     * @param position Позиция в цепочке (0 - в конец)
     * @return success Успешность операции
     */
    function addProcessor(
        address processor,
        uint256 position
    ) external onlyRole(PROCESSOR_MANAGER_ROLE) returns (bool success) {
        return PaymentOrchestrator(orchestrator).addProcessor(processor, position);
    }

    /**
     * @notice Настроить процессор для модуля
     * @param moduleId Идентификатор модуля
     * @param processorName Имя процессора
     * @param enabled Включен/выключен
     * @param configData Дополнительные данные для настройки
     * @return success Успешность операции
     */
    function configureProcessor(
        bytes32 moduleId,
        string memory processorName,
        bool enabled,
        bytes memory configData
    ) external onlyRole(PROCESSOR_MANAGER_ROLE) returns (bool success) {
        return PaymentOrchestrator(orchestrator).configureProcessor(moduleId, processorName, enabled, configData);
    }

    /**
     * @notice Получить список процессоров для модуля
     * @param moduleId Идентификатор модуля
     * @return processors Список процессоров
     */
    function getProcessors(bytes32 moduleId) external view override returns (address[] memory processors) {
        return PaymentOrchestrator(orchestrator).getProcessors(moduleId);
    }

    /**
     * @notice Получить имя компонента
     * @return name Имя компонента
     */
    function getName() external pure override returns (string memory name) {
        return GATEWAY_NAME;
    }

    /**
     * @notice Получить версию компонента
     * @return version Версия компонента
     */
    function getVersion() external pure override returns (string memory version) {
        return GATEWAY_VERSION;
    }

    /**
     * @notice Проверить, активен ли шлюз для модуля
     * @param moduleId Идентификатор модуля
     * @return enabled Активен ли шлюз
     */
    function isEnabled(bytes32 moduleId) external view override returns (bool enabled) {
        return PaymentOrchestrator(orchestrator).isEnabled(moduleId);
    }

    //    /**
    //     * @notice Обработать платеж с произвольными данными
    //     * @param moduleId Идентификатор модуля
    //     * @param paymentData Данные платежа
    //     * @return result Результат обработки
    //     * @return paymentId Идентификатор платежа
    //     */
    //    function processPaymentWithData(
    //        bytes32 moduleId,
    //        bytes calldata paymentData
    //    ) external override nonReentrant returns (PaymentResult result, bytes32 paymentId) {
    //        try {
    //            // Создаем контекст платежа напрямую из произвольных данных
    //            PaymentContextLibrary.PaymentContext memory context = PaymentContextLibrary.createContext(
    //                moduleId,
    //                msg.sender,          // По умолчанию отправитель - вызывающий контракт
    //                address(0),         // Получатель будет определен процессорами
    //                address(0),         // Токен будет определен из paymentData
    //                0,                  // Сумма будет определена из paymentData
    //                PaymentContextLibrary.PaymentOperation.PAYMENT,
    //                paymentData          // Данные для обработки процессорами
    //            );
    //
    //            // Запускаем обработку через цепочку процессоров
    //            // Флаг нативной валюты будет определен процессорами
    //            uint256 netAmount;
    //            (netAmount, paymentId) = _processPaymentThroughProcessors(context, false);
    //
    //            // Сохраняем результат платежа
    //            result = PaymentResult.SUCCESS;
    //            paymentResults[paymentId] = result;
    //
    //            return (result, paymentId);
    //        } catch Error(string memory reason) {
    //            // Обработка ошибки с сообщением
    //            result = PaymentResult.FAILED;
    //            return (result, bytes32(0));
    //        } catch {
    //            // Обработка ошибки без сообщения
    //            result = PaymentResult.FAILED;
    //            return (result, bytes32(0));
    //        }
    //    }

    /**
     * @notice Получить статус платежа
     * @param paymentId Идентификатор платежа
     * @return status Статус платежа
     */
    function getPaymentStatus(bytes32 paymentId) external view override returns (PaymentResult status) {
        // Возвращаем сохраненный статус платежа
        PaymentResult result = paymentResults[paymentId];

        // Если статус не найден, возвращаем FAILED
        if (result == PaymentResult(0)) {
            return PaymentResult.FAILED;
        }

        return result;
    }

    // Функция для получения оплаты в нативной валюте
    receive() external payable {}
}
