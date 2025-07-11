// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './interfaces/IGateway.sol';
import './interfaces/IProcessorRegistry.sol';
import './interfaces/IPaymentProcessor.sol';
import './PaymentContextLibrary.sol';
import '@openzeppelin/contracts/access/AccessControl.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/// @title PaymentGateway
/// @notice Платежный шлюз для маршрутизации платежей через цепочку процессоров
/// @dev Основная задача - координация обработки платежей через различные процессоры
contract PaymentGateway is IGateway, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using PaymentContextLibrary for PaymentContextLibrary.PaymentContext;

    // Constants
    bytes32 public constant PAYMENT_ADMIN_ROLE = keccak256('PAYMENT_ADMIN_ROLE');
    bytes32 public constant PROCESSOR_MANAGER_ROLE = keccak256('PROCESSOR_MANAGER_ROLE');

    // Имя и версия компонента
    string private constant GATEWAY_NAME = 'PaymentGateway';
    string private constant GATEWAY_VERSION = '1.0.0';

    // State variables
    address public immutable coreSystem;
    address public immutable processorRegistry;

    // Processor configuration for modules
    mapping(bytes32 => address[]) public moduleProcessors;
    mapping(bytes32 => mapping(string => bool)) public moduleProcessorConfig;

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
    event ProcessorAdded(address indexed processor, uint256 position);
    event ProcessorConfigured(bytes32 indexed moduleId, string processorName, bool enabled);

    /**
     * @dev Конструктор шлюза
     * @param _coreSystem Адрес системы ядра
     * @param _processorRegistry Адрес реестра процессоров
     */
    constructor(address _coreSystem, address _processorRegistry) {
        require(_coreSystem != address(0), 'PaymentGateway: core system is zero address');
        require(_processorRegistry != address(0), 'PaymentGateway: processor registry is zero address');

        coreSystem = _coreSystem;
        processorRegistry = _processorRegistry;

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

        // Создаем контекст платежа с использованием библиотеки
        PaymentContextLibrary.PaymentContext memory context = PaymentContextLibrary.createContext(
            moduleId,
            payer, // Отправитель
            address(0), // Получатель будет определен процессорами
            token, // Токен платежа
            amount, // Сумма платежа
            PaymentContextLibrary.PaymentOperation.PAYMENT, // Тип операции
            signature.length > 0 ? signature : new bytes(0) // Метаданные (подпись, если есть)
        );

        // Запускаем обработку через цепочку процессоров
        bytes32 paymentId;
        (netAmount, paymentId) = _processPaymentThroughProcessors(context, isNativeToken);

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
    function _processPaymentThroughProcessors(
        PaymentContextLibrary.PaymentContext memory context,
        bool isNativeToken
    ) internal returns (uint256 netAmount, bytes32 paymentId) {
        bytes32 moduleId = context.packed.moduleId;
        address token = context.packed.token;
        uint256 amount = context.packed.originalAmount;

        // Получаем цепочку процессоров для модуля
        address[] memory processors = moduleProcessors[moduleId];
        bytes memory contextBytes = abi.encode(context);

        // Проходим по всем процессорам в цепочке
        for (uint256 i = 0; i < processors.length; i++) {
            address processor = processors[i];
            if (processor == address(0)) continue;

            string memory processorName = IPaymentProcessor(processor).getName();
            if (!moduleProcessorConfig[moduleId][processorName]) continue;

            // Проверяем применимость процессора
            if (!IPaymentProcessor(processor).isApplicable(contextBytes)) continue;

            // Обрабатываем контекст процессором
            (IPaymentProcessor.ProcessResult result, bytes memory updatedContext) = IPaymentProcessor(processor)
                .process(contextBytes);

            // Обрабатываем ошибки процессора
            if (result == IPaymentProcessor.ProcessResult.FAILED) {
                context = abi.decode(updatedContext, (PaymentContextLibrary.PaymentContext));
                revert(context.results.errorMessage);
            }

            // Обновляем контекст для следующего процессора
            contextBytes = updatedContext;
        }

        // Декодируем финальный контекст
        context = abi.decode(contextBytes, (PaymentContextLibrary.PaymentContext));

        // Проверяем успешность обработки
        if (!context.packed.success) {
            revert(context.results.errorMessage);
        }

        // Рассчитываем чистую сумму
        netAmount = amount - context.results.feeAmount;
        paymentId = context.results.paymentId;

        // Переводим комиссию, если необходимо
        if (context.results.feeAmount > 0 && context.packed.recipient != address(0)) {
            if (isNativeToken) {
                payable(context.packed.recipient).transfer(context.results.feeAmount);
            } else {
                IERC20(token).safeTransfer(context.packed.recipient, context.results.feeAmount);
            }
        }

        return (netAmount, paymentId);
    }

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
        // Получаем список процессоров для модуля
        address[] memory processors = moduleProcessors[moduleId];

        // Ищем процессор конвертации (OracleProcessor)
        for (uint256 i = 0; i < processors.length; i++) {
            address processor = processors[i];
            if (processor == address(0)) continue;

            // Проверяем, что это OracleProcessor по имени
            try IPaymentProcessor(processor).getName() returns (string memory name) {
                if (keccak256(abi.encodePacked(name)) == keccak256(abi.encodePacked('OracleProcessor'))) {
                    // Делегируем вызов процессору конвертации
                    try IPaymentProcessor(processor).convertAmount(moduleId, fromToken, toToken, amount) returns (
                        uint256 result
                    ) {
                        return result;
                    } catch {
                        // Если произошла ошибка, продолжаем поиск других процессоров
                    }
                }
            } catch {
                // Если произошла ошибка при получении имени, продолжаем
            }
        }

        // Если подходящий процессор не найден, возвращаем исходную сумму
        return amount;
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
        // Получаем процессор фильтрации токенов из реестра
        try IProcessorRegistry(processorRegistry).getProcessorByName('TokenFilter') returns (address tokenFilter) {
            if (tokenFilter != address(0)) {
                // Делегируем вызов процессору фильтрации токенов
                try IPaymentProcessor(tokenFilter).isPairSupported(moduleId, fromToken, toToken) returns (bool result) {
                    return result;
                } catch {
                    // Если произошла ошибка, возвращаем true (упрощенная версия)
                }
            }
        } catch {
            // Если произошла ошибка при получении процессора, возвращаем true
        }

        return true;
    }

    /**
     * @notice Делегирующий метод для получения списка поддерживаемых токенов
     * @dev Делегирует вызов TokenFilterProcessor
     * @param moduleId Идентификатор модуля
     * @return tokens Список поддерживаемых токенов
     */
    function getSupportedTokens(bytes32 moduleId) external view override returns (address[] memory tokens) {
        // Получаем процессор фильтрации токенов из реестра
        try IProcessorRegistry(processorRegistry).getProcessorByName('TokenFilter') returns (address tokenFilter) {
            if (tokenFilter != address(0)) {
                // Делегируем вызов процессору фильтрации токенов
                try IPaymentProcessor(tokenFilter).getAllowedTokens(moduleId) returns (address[] memory result) {
                    return result;
                } catch {
                    // Если произошла ошибка, возвращаем упрощенный список
                }
            }
        } catch {
            // Если произошла ошибка при получении процессора, возвращаем упрощенный список
        }

        // Упрощенная версия - всегда содержит нативную валюту
        address[] memory defaultTokens = new address[](1);
        defaultTokens[0] = address(0);
        return defaultTokens;
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
        require(processor != address(0), 'PaymentGateway: processor is zero address');

        // Проверяем, что процессор соответствует интерфейсу
        require(IPaymentProcessor(processor).getVersion().length > 0, 'PaymentGateway: invalid processor');

        // Добавляем процессор в реестр, если это новый процессор
        IProcessorRegistry registry = IProcessorRegistry(processorRegistry);
        string memory processorName = IPaymentProcessor(processor).getName();

        if (registry.getProcessorByName(processorName) == address(0)) {
            registry.registerProcessor(processor, position);
        }

        emit ProcessorAdded(processor, position);
        return true;
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
        // Получаем адрес процессора из реестра
        IProcessorRegistry registry = IProcessorRegistry(processorRegistry);
        address processor = registry.getProcessorByName(processorName);
        require(processor != address(0), 'PaymentGateway: processor not found');

        // Устанавливаем конфигурацию для модуля
        moduleProcessorConfig[moduleId][processorName] = enabled;

        // Проверяем, есть ли процессор в списке для модуля
        bool found = false;
        address[] storage processors = moduleProcessors[moduleId];
        for (uint256 i = 0; i < processors.length; i++) {
            if (processors[i] == processor) {
                found = true;
                break;
            }
        }

        // Если процессора нет в списке, добавляем его
        if (!found) {
            processors.push(processor);
        }

        // Настраиваем процессор
        if (configData.length > 0) {
            IPaymentProcessor(processor).configure(moduleId, configData);
        }

        emit ProcessorConfigured(moduleId, processorName, enabled);
        return true;
    }

    /**
     * @notice Получить список процессоров для модуля
     * @param moduleId Идентификатор модуля
     * @return processors Список процессоров
     */
    function getProcessors(bytes32 moduleId) external view override returns (address[] memory processors) {
        return moduleProcessors[moduleId];
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
        // Шлюз активен, если для модуля зарегистрирован хотя бы один процессор
        return moduleProcessors[moduleId].length > 0;
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
