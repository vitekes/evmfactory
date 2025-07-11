// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title PaymentContextLibrary
/// @notice Библиотека для работы с контекстом платежа
/// @dev Содержит структуры и методы для работы с платежными данными
library PaymentContextLibrary {
    /// @notice Состояния обработки платежа
    enum ProcessingState {
        INITIALIZED,    // Платеж инициализирован
        VALIDATING,     // Проверка входных данных
        PROCESSING,     // Обработка платежа
        CONVERTING,     // Конвертация валют
        CALCULATING_FEES, // Расчет комиссий
        APPLYING_DISCOUNT, // Применение скидок
        TRANSFERRING,   // Перевод средств
        COMPLETED,      // Обработка завершена
        FAILED          // Обработка завершилась ошибкой
    }

    /// @notice Тип операции платежа
    enum PaymentOperation {
        PAYMENT,        // Обычный платеж
        SUBSCRIPTION,   // Платеж по подписке
        MARKETPLACE,    // Платеж на маркетплейсе
        ESCROW,         // Депонирование средств
        REFUND          // Возврат средств
    }

    /// @notice Упакованные данные контекста для экономии газа
    struct PackedData {
        bytes32 moduleId;              // Идентификатор модуля
        address sender;                // Отправитель средств
        address recipient;             // Получатель средств
        address token;                 // Адрес токена платежа
        uint128 originalAmount;        // Исходная сумма платежа (упаковано)
        uint128 processedAmount;       // Текущая сумма после обработки (упаковано)
        uint8 operation;               // Тип операции (упаковано из enum)
        uint8 state;                   // Текущее состояние обработки (упаковано из enum)
        uint32 timestamp;              // Время создания контекста (упаковано)
        uint32 deadline;               // Срок действия, если применимо (упаковано)
        bool success;                  // Флаг успешности операции
    }

    /// @notice Результаты обработки процессорами
    struct ProcessorResults {
        bytes32 paymentId;             // Уникальный идентификатор платежа
        uint64 feeAmount;              // Сумма комиссии (упаковано)
        uint64 discountAmount;         // Сумма скидки (упаковано)
        uint16 discountPercent;        // Процент скидки (в базисных пунктах)
        string[] processorNames;       // Имена процессоров, обработавших контекст
        uint8[] processorResults;      // Результаты обработки процессорами
        string errorMessage;           // Сообщение об ошибке, если есть
    }

    /// @notice Оптимизированная структура контекста платежа
    struct PaymentContext {
        PackedData packed;              // Упакованные основные данные
        ProcessorResults results;      // Результаты обработки процессорами
        bytes metadata;                // Произвольные данные для обработчиков
    }

    /// @notice Создать базовый контекст платежа
    /// @param moduleId Идентификатор модуля
    /// @param sender Отправитель
    /// @param recipient Получатель
    /// @param token Токен
    /// @param amount Сумма
    /// @param operation Тип операции
    /// @param metadata Дополнительные данные
    /// @return context Созданный контекст
    function createContext(
        bytes32 moduleId,
        address sender,
        address recipient,
        address token,
        uint256 amount,
        PaymentOperation operation,
        bytes memory metadata
    ) internal view returns (PaymentContext memory context) {
        // Проверка на переполнение при упаковке
        require(amount <= type(uint128).max, "Amount too large for packing");

        // Инициализация упакованных данных
        context.packed.moduleId = moduleId;
        context.packed.sender = sender;
        context.packed.recipient = recipient;
        context.packed.token = token;
        context.packed.originalAmount = uint128(amount);
        context.packed.processedAmount = uint128(amount);
        context.packed.operation = uint8(operation);
        context.packed.state = uint8(ProcessingState.INITIALIZED);
        context.packed.success = false;
        context.packed.timestamp = uint32(block.timestamp);

        // Инициализация результатов
        context.results.paymentId = keccak256(abi.encode(
            moduleId, sender, recipient, token, amount, block.timestamp
        ));
        context.results.processorNames = new string[](0);
        context.results.processorResults = new uint8[](0);

        // Установка метаданных
        context.metadata = metadata;

        return context;
    }

    /// @notice Обновить состояние контекста
    /// @param context Исходный контекст
    /// @param newState Новое состояние
    /// @return updatedContext Обновленный контекст
    function updateState(
        PaymentContext memory context,
        ProcessingState newState
    ) internal pure returns (PaymentContext memory) {
        context.packed.state = uint8(newState);
        return context;
    }

    /// @notice Добавить запись о процессоре в историю обработки
    /// @param context Исходный контекст
    /// @param processorName Имя процессора
    /// @param result Результат обработки
    /// @return Обновленный контекст
    function addProcessorResult(
        PaymentContext memory context,
        string memory processorName,
        uint8 result
    ) internal pure returns (PaymentContext memory) {
        // Создаем новые массивы с увеличенным размером
        uint256 currentLength = context.results.processorNames.length;
        string[] memory newProcessorNames = new string[](currentLength + 1);
        uint8[] memory newProcessorResults = new uint8[](currentLength + 1);

        // Эффективное копирование существующих данных
        if (currentLength > 0) {
            for (uint256 i = 0; i < currentLength; i++) {
                newProcessorNames[i] = context.results.processorNames[i];
                newProcessorResults[i] = context.results.processorResults[i];
            }
        }

        // Добавляем новую запись
        newProcessorNames[currentLength] = processorName;
        newProcessorResults[currentLength] = result;

        // Обновляем массивы в контексте
        context.results.processorNames = newProcessorNames;
        context.results.processorResults = newProcessorResults;

        return context;
    }

    /// @notice Установить сумму комиссии
    /// @param context Исходный контекст
    /// @param feeAmount Сумма комиссии
    /// @return Обновленный контекст
    function setFeeAmount(
        PaymentContext memory context,
        uint256 feeAmount
    ) internal pure returns (PaymentContext memory) {
        require(feeAmount <= type(uint64).max, "Fee amount too large for packing");
        context.results.feeAmount = uint64(feeAmount);
        return context;
    }

    /// @notice Установить сумму скидки
    /// @param context Исходный контекст
    /// @param discountAmount Сумма скидки
    /// @param discountPercent Процент скидки (опционально)
    /// @return Обновленный контекст
    function setDiscountAmount(
        PaymentContext memory context,
        uint256 discountAmount,
        uint16 discountPercent
    ) internal pure returns (PaymentContext memory) {
        require(discountAmount <= type(uint64).max, "Discount amount too large for packing");
        context.results.discountAmount = uint64(discountAmount);
        context.results.discountPercent = discountPercent;
        return context;
    }

    /// @notice Установить сообщение об ошибке
    /// @param context Исходный контекст
    /// @param errorMessage Сообщение об ошибке
    /// @return Обновленный контекст
    function setErrorMessage(
        PaymentContext memory context,
        string memory errorMessage
    ) internal pure returns (PaymentContext memory) {
        context.results.errorMessage = errorMessage;
        context.packed.success = false;
        return context;
    }

    /// @notice Установить успешность операции
    /// @param context Исходный контекст
    /// @param success Флаг успешности
    /// @return Обновленный контекст
    function setSuccess(
        PaymentContext memory context,
        bool success
    ) internal pure returns (PaymentContext memory) {
        context.packed.success = success;
        return context;
    }

    /// @notice Обновить обработанную сумму
    /// @param context Исходный контекст
    /// @param processedAmount Новая обработанная сумма
    /// @return Обновленный контекст
    function updateProcessedAmount(
        PaymentContext memory context,
        uint256 processedAmount
    ) internal pure returns (PaymentContext memory) {
        require(processedAmount <= type(uint128).max, "Amount too large for packing");
        context.packed.processedAmount = uint128(processedAmount);
        return context;
    }

    /// @notice Сериализовать контекст в байты
    /// @param context Контекст для сериализации
    /// @return Сериализованный контекст
    function serializeContext(
        PaymentContext memory context
    ) internal pure returns (bytes memory) {
        return abi.encode(context);
    }

    /// @notice Десериализовать контекст из байтов
    /// @param data Сериализованный контекст
    /// @return Десериализованный контекст
    function deserializeContext(
        bytes memory data
    ) internal pure returns (PaymentContext memory) {
        return abi.decode(data, (PaymentContext));
    }

    /// @notice Получить модуль из контекста
    /// @param context Контекст платежа
    /// @return Идентификатор модуля
    function getModuleId(PaymentContext memory context) internal pure returns (bytes32) {
        return context.packed.moduleId;
    }

    /// @notice Получить отправителя из контекста
    /// @param context Контекст платежа
    /// @return Адрес отправителя
    function getSender(PaymentContext memory context) internal pure returns (address) {
        return context.packed.sender;
    }

    /// @notice Получить получателя из контекста
    /// @param context Контекст платежа
    /// @return Адрес получателя
    function getRecipient(PaymentContext memory context) internal pure returns (address) {
        return context.packed.recipient;
    }

    /// @notice Получить токен из контекста
    /// @param context Контекст платежа
    /// @return Адрес токена
    function getToken(PaymentContext memory context) internal pure returns (address) {
        return context.packed.token;
    }

    /// @notice Получить исходную сумму из контекста
    /// @param context Контекст платежа
    /// @return Исходная сумма
    function getOriginalAmount(PaymentContext memory context) internal pure returns (uint256) {
        return uint256(context.packed.originalAmount);
    }

    /// @notice Получить обработанную сумму из контекста
    /// @param context Контекст платежа
    /// @return Обработанная сумма
    function getProcessedAmount(PaymentContext memory context) internal pure returns (uint256) {
        return uint256(context.packed.processedAmount);
    }

    /// @notice Получить тип операции из контекста
    /// @param context Контекст платежа
    /// @return Тип операции
    function getOperation(PaymentContext memory context) internal pure returns (PaymentOperation) {
        return PaymentOperation(context.packed.operation);
    }

    /// @notice Получить состояние из контекста
    /// @param context Контекст платежа
    /// @return Состояние
    function getState(PaymentContext memory context) internal pure returns (ProcessingState) {
        return ProcessingState(context.packed.state);
    }

    /// @notice Получить флаг успешности из контекста
    /// @param context Контекст платежа
    /// @return Флаг успешности
    function isSuccessful(PaymentContext memory context) internal pure returns (bool) {
        return context.packed.success;
    }
}
