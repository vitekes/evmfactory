// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title ProcessorMetadataLib
/// @notice Библиотека для работы с унифицированными метаданными процессоров
/// @dev Предоставляет общую структуру и функции для работы с метаданными
library ProcessorMetadataLib {
    /// @notice Типы процессоров в системе
    enum ProcessorType {
        UNKNOWN, // Неизвестный тип
        PRICE_ORACLE, // Процессор конвертации валют
        FEE, // Процессор комиссий
        DISCOUNT, // Процессор скидок
        TOKEN_FILTER // Процессор фильтрации токенов
    }

    /// @notice Унифицированная структура метаданных процессора
    struct ProcessorMetadata {
        ProcessorType processorType; // Тип процессора
        bytes processorData; // Специфичные данные процессора
        uint256 priority; // Приоритет обработки (меньшее значение = выше приоритет)
        bool required; // Обязательность выполнения
    }

    /// @notice Создать базовые метаданные процессора
    /// @param processorType Тип процессора
    /// @param priority Приоритет обработки
    /// @param required Обязательность выполнения
    /// @return metadata Метаданные процессора без специфичных данных
    function createBaseMetadata(
        ProcessorType processorType,
        uint256 priority,
        bool required
    ) internal pure returns (ProcessorMetadata memory metadata) {
        return
            ProcessorMetadata({
                processorType: processorType,
                processorData: '',
                priority: priority,
                required: required
            });
    }

    /// @notice Создать метаданные процессора со специфичными данными
    /// @param processorType Тип процессора
    /// @param processorData Специфичные данные процессора
    /// @param priority Приоритет обработки
    /// @param required Обязательность выполнения
    /// @return metadata Полные метаданные процессора
    function createMetadata(
        ProcessorType processorType,
        bytes memory processorData,
        uint256 priority,
        bool required
    ) internal pure returns (ProcessorMetadata memory metadata) {
        return
            ProcessorMetadata({
                processorType: processorType,
                processorData: processorData,
                priority: priority,
                required: required
            });
    }

    /// @notice Получить тип процессора из имени
    /// @param processorName Имя процессора
    /// @return processorType Тип процессора
    function getProcessorTypeFromName(string memory processorName) internal pure returns (ProcessorType processorType) {
        bytes32 nameHash = keccak256(bytes(processorName));

        if (nameHash == keccak256(bytes('PriceOracle'))) {
            return ProcessorType.PRICE_ORACLE;
        } else if (nameHash == keccak256(bytes('FeeProcessor'))) {
            return ProcessorType.FEE;
        } else if (nameHash == keccak256(bytes('DiscountProcessor'))) {
            return ProcessorType.DISCOUNT;
        } else if (nameHash == keccak256(bytes('TokenFilter'))) {
            return ProcessorType.TOKEN_FILTER;
        } else {
            return ProcessorType.UNKNOWN;
        }
    }

    /// @notice Создать метаданные для процессора конвертации валют
    /// @param needsConversion Требуется ли конвертация
    /// @param targetToken Целевой токен для конвертации
    /// @param priority Приоритет обработки
    /// @param required Обязательность выполнения
    /// @return metadata Метаданные процессора конвертации
    function createOracleMetadata(
        bool needsConversion,
        address targetToken,
        uint256 priority,
        bool required
    ) internal pure returns (ProcessorMetadata memory metadata) {
        bytes memory processorData = abi.encode(needsConversion, targetToken);
        return createMetadata(ProcessorType.PRICE_ORACLE, processorData, priority, required);
    }

    /// @notice Создать метаданные для процессора скидок с подписью
    /// @param signatureData Данные подписи скидки
    /// @param signatureHash Хеш подписи
    /// @param priority Приоритет обработки
    /// @param required Обязательность выполнения
    /// @return metadata Метаданные процессора скидок
    function createDiscountSignatureMetadata(
        bytes memory signatureData,
        bytes32 signatureHash,
        uint256 priority,
        bool required
    ) internal pure returns (ProcessorMetadata memory metadata) {
        bytes memory processorData = abi.encode(signatureHash, signatureData);
        return createMetadata(ProcessorType.DISCOUNT, processorData, priority, required);
    }

    /// @notice Создать метаданные для процессора комиссий
    /// @param customFeePercent Нестандартный процент комиссии (если применимо)
    /// @param feeRecipient Получатель комиссии (если отличается от стандартного)
    /// @param priority Приоритет обработки
    /// @param required Обязательность выполнения
    /// @return metadata Метаданные процессора комиссий
    function createFeeMetadata(
        uint16 customFeePercent,
        address feeRecipient,
        uint256 priority,
        bool required
    ) internal pure returns (ProcessorMetadata memory metadata) {
        bytes memory processorData = abi.encode(customFeePercent, feeRecipient);
        return createMetadata(ProcessorType.FEE, processorData, priority, required);
    }

    /// @notice Создать метаданные для процессора фильтрации токенов
    /// @param allowOverride Разрешить обход стандартных правил фильтрации
    /// @param priority Приоритет обработки
    /// @param required Обязательность выполнения
    /// @return metadata Метаданные процессора фильтрации токенов
    function createTokenFilterMetadata(
        bool allowOverride,
        uint256 priority,
        bool required
    ) internal pure returns (ProcessorMetadata memory metadata) {
        bytes memory processorData = abi.encode(allowOverride);
        return createMetadata(ProcessorType.TOKEN_FILTER, processorData, priority, required);
    }

    /// @notice Упаковать несколько метаданных в одну структуру байтов
    /// @param metadataArray Массив структур метаданных
    /// @return packedMetadata Упакованные метаданные
    function packMetadata(
        ProcessorMetadata[] memory metadataArray
    ) internal pure returns (bytes memory packedMetadata) {
        return abi.encode(metadataArray);
    }

    /// @notice Распаковать метаданные из байтов
    /// @param packedMetadata Упакованные метаданные
    /// @return metadataArray Массив структур метаданных
    function unpackMetadata(
        bytes memory packedMetadata
    ) internal pure returns (ProcessorMetadata[] memory metadataArray) {
        if (packedMetadata.length == 0) {
            return new ProcessorMetadata[](0);
        }

        return abi.decode(packedMetadata, (ProcessorMetadata[]));
    }

    /// @notice Найти метаданные для конкретного типа процессора
    /// @param metadataArray Массив структур метаданных
    /// @param processorType Тип процессора
    /// @return found Найдены ли метаданные
    /// @return metadata Найденные метаданные
    function findMetadataByType(
        ProcessorMetadata[] memory metadataArray,
        ProcessorType processorType
    ) internal pure returns (bool found, ProcessorMetadata memory metadata) {
        for (uint256 i = 0; i < metadataArray.length; i++) {
            if (metadataArray[i].processorType == processorType) {
                return (true, metadataArray[i]);
            }
        }

        // Возвращаем пустую структуру, если ничего не найдено
        return (false, createBaseMetadata(ProcessorType.UNKNOWN, 0, false));
    }
}
