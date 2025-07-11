// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../BaseProcessor.sol';
import '../PaymentContextLibrary.sol';
import '../ProcessorMetadataLib.sol';
import '../../lib/SignatureLib.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';

/// @title DiscountProcessor
/// @notice Процессор для управления скидками в платежной системе
/// @dev Применяет скидки на основе подписанных разрешений или предварительно настроенных правил
contract DiscountProcessor is BaseProcessor {
    using PaymentContextLibrary for PaymentContextLibrary.PaymentContext;
    using ECDSA for bytes32;

    // Constants
    bytes32 public constant DISCOUNT_MANAGER_ROLE = keccak256('DISCOUNT_MANAGER_ROLE');
    string private constant _PROCESSOR_NAME = 'DiscountProcessor';
    string private constant _PROCESSOR_VERSION = '1.0.0';
    uint16 public constant MAX_DISCOUNT_BPS = 10000; // 100%

    // EIP-712 Domain Separator
    bytes32 private immutable DOMAIN_SEPARATOR;

    // Discount types
    enum DiscountType {
        NONE, // Нет скидки
        FIXED, // Фиксированная сумма
        PERCENTAGE, // Процент от суммы
        SIGNATURE // Скидка по подписи
    }

    // Структура правила скидки
    struct DiscountRule {
        DiscountType discountType; // Тип скидки
        uint16 percentBps; // Процент скидки в базисных пунктах (1/100 процента)
        uint256 fixedAmount; // Фиксированная сумма скидки
        uint256 minAmount; // Минимальная сумма для применения скидки
        uint64 validUntil; // Срок действия правила
        bool active; // Активность правила
    }

    // Структура для хранения информации о разовых скидках
    struct SignatureDiscount {
        address user; // Пользователь, для которого действует скидка
        bytes32 moduleId; // Идентификатор модуля
        uint16 discountPercent; // Процент скидки
        uint256 maxAmount; // Максимальная сумма скидки
        uint64 validUntil; // Срок действия
        bytes32 skuOrListingId; // SKU или ID листинга (опционально)
        bool used; // Использована ли скидка
    }

    // State variables
    mapping(bytes32 => bool) public moduleEnabled; // moduleId => enabled
    mapping(bytes32 => mapping(address => mapping(bytes32 => DiscountRule))) public discountRules; // moduleId => token => ruleId => rule
    mapping(bytes32 => address[]) public validSigners; // moduleId => список валидных подписантов
    mapping(bytes32 => bool) public usedSignatures; // hash => использована ли подпись
    mapping(bytes32 => bytes32[]) public moduleDiscountRules; // moduleId => список всех правил

    // Events
    event DiscountRuleCreated(
        bytes32 indexed moduleId,
        address indexed token,
        bytes32 indexed ruleId,
        DiscountType discountType,
        uint16 percentBps,
        uint256 fixedAmount
    );
    event DiscountRuleUpdated(bytes32 indexed moduleId, address indexed token, bytes32 indexed ruleId, bool active);
    event DiscountApplied(
        bytes32 indexed moduleId,
        address indexed token,
        bytes32 indexed ruleId,
        uint256 amount,
        uint256 discountAmount,
        address user
    );
    event ModuleConfigured(bytes32 indexed moduleId, bool enabled);
    event ValidSignerAdded(bytes32 indexed moduleId, address signer);
    event ValidSignerRemoved(bytes32 indexed moduleId, address signer);
    event SignatureDiscountApplied(
        bytes32 indexed moduleId,
        address indexed user,
        uint256 amount,
        uint256 discountAmount,
        bytes32 signatureHash
    );

    /**
     * @dev Конструктор
     */
    constructor() BaseProcessor() {
        _grantRole(DISCOUNT_MANAGER_ROLE, msg.sender);

        // Инициализация EIP-712 domain separator
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(_PROCESSOR_NAME)),
                keccak256(bytes(_PROCESSOR_VERSION)),
                block.chainid,
                address(this)
            )
        );
    }

    /**
     * @notice Получить имя процессора
     * @return name Имя процессора
     */
    function getName() public pure override returns (string memory name) {
        return _PROCESSOR_NAME;
    }

    /**
     * @notice Получить версию процессора
     * @return version Версия процессора
     */
    function getVersion() public pure override returns (string memory version) {
        return _PROCESSOR_VERSION;
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
        // Проверяем наличие дополнительных данных для скидки по подписи
        bool hasSignatureDiscount = false;
        bytes memory signature;
        bytes32 discountHash;

        if (context.metadata.length > 0) {
            // Сначала пробуем извлечь данные из нового формата метаданных
            try this.extractDiscountMetadata(context.metadata) returns (bytes32 hash, bytes memory sig) {
                if (hash != bytes32(0) && sig.length > 0) {
                    hasSignatureDiscount = true;
                    signature = sig;
                    discountHash = hash;
                }
            } catch {
                // Если не получилось декодировать новый формат, пробуем старый
            }

            // Для обратной совместимости пробуем старый формат
            if (!hasSignatureDiscount) {
                try this.decodeSignatureFromMetadata(context.metadata) returns (bytes memory sig, bytes32 hash) {
                    hasSignatureDiscount = true;
                    signature = sig;
                    discountHash = hash;
                } catch {
                    // Если не получилось декодировать подпись, продолжаем без нее
                }
            }
        }

        uint256 discountAmount = 0;
        bytes32 appliedRuleId;

        // Сначала проверяем скидку по подписи, если она есть
        if (hasSignatureDiscount) {
            (bool signatureValid, uint16 discountPercent) = validateDiscountSignature(
                discountHash,
                signature,
                context.moduleId,
                context.sender
            );

            if (signatureValid && !usedSignatures[discountHash]) {
                // Отмечаем подпись как использованную
                usedSignatures[discountHash] = true;

                // Вычисляем скидку
                discountAmount = (context.processedAmount * uint256(discountPercent)) / 10000;

                emit SignatureDiscountApplied(
                    context.moduleId,
                    context.sender,
                    context.processedAmount,
                    discountAmount,
                    discountHash
                );
            }
        }

        // Если не применена скидка по подписи, ищем подходящее правило скидки
        if (discountAmount == 0) {
            (discountAmount, appliedRuleId) = findBestDiscount(
                context.moduleId,
                context.token,
                context.processedAmount,
                context.sender
            );

            if (discountAmount > 0) {
                emit DiscountApplied(
                    context.moduleId,
                    context.token,
                    appliedRuleId,
                    context.processedAmount,
                    discountAmount,
                    context.sender
                );
            }
        }

        // Если скидка не найдена, пропускаем обработку
        if (discountAmount == 0) {
            context = PaymentContextLibrary.addProcessorResult(context, getName(), uint8(ProcessResult.SKIPPED));
            return (ProcessResult.SKIPPED, abi.encode(context));
        }

        // Проверяем, что скидка не превышает сумму платежа
        if (discountAmount >= context.processedAmount) {
            discountAmount = context.processedAmount - 1; // Оставляем хотя бы 1 единицу
        }

        // Применяем скидку
        context.discountAmount += discountAmount;
        context.discountPercent = uint16((discountAmount * 10000) / context.originalAmount); // Запоминаем процент от исходной суммы
        context.processedAmount -= discountAmount;

        // Обновляем состояние
        context.state = PaymentContextLibrary.ProcessingState.APPLYING_DISCOUNT;

        // Добавляем запись о процессоре
        context = PaymentContextLibrary.addProcessorResult(context, getName(), uint8(ProcessResult.MODIFIED));

        return (ProcessResult.MODIFIED, abi.encode(context));
    }

    /**
     * @dev Внутренняя реализация проверки применимости
     * @param context Контекст платежа
     * @return applicable Применим ли процессор
     */
    function _isApplicableInternal(
        PaymentContextLibrary.PaymentContext memory context
    ) internal view override returns (bool applicable) {
        // Проверяем наличие скидки в новом формате метаданных
        if (context.metadata.length > 0) {
            try this.extractDiscountMetadata(context.metadata) returns (
                bytes32 signatureHash,
                bytes memory signatureData
            ) {
                if (signatureHash != bytes32(0) && signatureData.length > 0) {
                    return true;
                }
            } catch {
                // Продолжаем проверку в старом формате, если новый формат не распознан
            }

            // Для обратной совместимости проверяем старый формат
            try this.decodeSignatureFromMetadata(context.metadata) returns (bytes memory, bytes32) {
                return true;
            } catch {
                // Продолжаем проверку правил, если подпись не декодируется
            }
        }

        // Проверяем наличие правил скидки для модуля и токена
        bytes32[] memory rules = moduleDiscountRules[context.moduleId];
        for (uint256 i = 0; i < rules.length; i++) {
            DiscountRule memory rule = discountRules[context.moduleId][context.token][rules[i]];
            if (rule.active && block.timestamp <= rule.validUntil && context.processedAmount >= rule.minAmount) {
                return true;
            }
        }

        return false;
    }

    /**
     * @notice Создать правило скидки
     * @param moduleId Идентификатор модуля
     * @param token Адрес токена
     * @param ruleId Идентификатор правила
     * @param discountType Тип скидки
     * @param percentBps Процент скидки в базисных пунктах
     * @param fixedAmount Фиксированная сумма скидки
     * @param minAmount Минимальная сумма для применения скидки
     * @param validUntil Срок действия правила
     */
    function createDiscountRule(
        bytes32 moduleId,
        address token,
        bytes32 ruleId,
        DiscountType discountType,
        uint16 percentBps,
        uint256 fixedAmount,
        uint256 minAmount,
        uint64 validUntil
    ) external {
        // Проверяем роль с учетом централизованного управления ролями
        require(
            _hasProcessorRole(DISCOUNT_MANAGER_ROLE, msg.sender) || hasRole(DISCOUNT_MANAGER_ROLE, msg.sender),
            'DiscountProcessor: caller is not a discount manager'
        );
        require(discountType != DiscountType.NONE, 'DiscountProcessor: invalid discount type');
        require(validUntil > block.timestamp, 'DiscountProcessor: invalid expiration time');
        require(percentBps <= MAX_DISCOUNT_BPS, 'DiscountProcessor: discount percent too high');

        if (discountType == DiscountType.PERCENTAGE) {
            require(percentBps > 0, 'DiscountProcessor: percent must be positive');
        } else if (discountType == DiscountType.FIXED) {
            require(fixedAmount > 0, 'DiscountProcessor: fixed amount must be positive');
        }

        // Проверяем, не существует ли уже правило с таким ID
        DiscountRule storage existingRule = discountRules[moduleId][token][ruleId];
        require(
            existingRule.validUntil == 0 || existingRule.validUntil < block.timestamp,
            'DiscountProcessor: rule already exists'
        );

        // Создаем новое правило
        discountRules[moduleId][token][ruleId] = DiscountRule({
            discountType: discountType,
            percentBps: percentBps,
            fixedAmount: fixedAmount,
            minAmount: minAmount,
            validUntil: validUntil,
            active: true
        });

        // Добавляем ID правила в список для модуля, если его еще нет
        bool ruleExists = false;
        for (uint256 i = 0; i < moduleDiscountRules[moduleId].length; i++) {
            if (moduleDiscountRules[moduleId][i] == ruleId) {
                ruleExists = true;
                break;
            }
        }

        if (!ruleExists) {
            moduleDiscountRules[moduleId].push(ruleId);
        }

        emit DiscountRuleCreated(moduleId, token, ruleId, discountType, percentBps, fixedAmount);
    }

    /**
     * @notice Обновить активность правила скидки
     * @param moduleId Идентификатор модуля
     * @param token Адрес токена
     * @param ruleId Идентификатор правила
     * @param active Активность правила
     */
    function updateDiscountRuleStatus(bytes32 moduleId, address token, bytes32 ruleId, bool active) external {
        // Проверяем роль с учетом централизованного управления ролями
        require(
            _hasProcessorRole(DISCOUNT_MANAGER_ROLE, msg.sender) || hasRole(DISCOUNT_MANAGER_ROLE, msg.sender),
            'DiscountProcessor: caller is not a discount manager'
        );
        DiscountRule storage rule = discountRules[moduleId][token][ruleId];
        require(rule.validUntil > block.timestamp, 'DiscountProcessor: rule expired or not found');

        rule.active = active;

        emit DiscountRuleUpdated(moduleId, token, ruleId, active);
    }

    /**
     * @notice Продлить срок действия правила скидки
     * @param moduleId Идентификатор модуля
     * @param token Адрес токена
     * @param ruleId Идентификатор правила
     * @param validUntil Новый срок действия правила
     */
    function extendDiscountRuleValidity(bytes32 moduleId, address token, bytes32 ruleId, uint64 validUntil) external {
        // Проверяем роль с учетом централизованного управления ролями
        require(
            _hasProcessorRole(DISCOUNT_MANAGER_ROLE, msg.sender) || hasRole(DISCOUNT_MANAGER_ROLE, msg.sender),
            'DiscountProcessor: caller is not a discount manager'
        );
        DiscountRule storage rule = discountRules[moduleId][token][ruleId];
        require(rule.validUntil > 0, 'DiscountProcessor: rule not found');
        require(validUntil > block.timestamp, 'DiscountProcessor: invalid expiration time');

        rule.validUntil = validUntil;

        emit DiscountRuleUpdated(moduleId, token, ruleId, rule.active);
    }

    /**
     * @notice Добавить валидного подписанта для скидок
     * @param moduleId Идентификатор модуля
     * @param signer Адрес подписанта
     */
    function addValidSigner(bytes32 moduleId, address signer) external {
        // Проверяем роль с учетом централизованного управления ролями
        require(
            _hasProcessorRole(PROCESSOR_ADMIN_ROLE, msg.sender) || hasRole(PROCESSOR_ADMIN_ROLE, msg.sender),
            'DiscountProcessor: caller is not a processor admin'
        );
        require(signer != address(0), 'DiscountProcessor: zero address signer');

        // Проверяем, что подписант еще не добавлен
        for (uint256 i = 0; i < validSigners[moduleId].length; i++) {
            if (validSigners[moduleId][i] == signer) {
                return; // Подписант уже в списке
            }
        }

        validSigners[moduleId].push(signer);

        emit ValidSignerAdded(moduleId, signer);
    }

    /**
     * @notice Удалить валидного подписанта для скидок
     * @param moduleId Идентификатор модуля
     * @param signer Адрес подписанта
     */
    function removeValidSigner(bytes32 moduleId, address signer) external {
        // Проверяем роль с учетом централизованного управления ролями
        require(
            _hasProcessorRole(PROCESSOR_ADMIN_ROLE, msg.sender) || hasRole(PROCESSOR_ADMIN_ROLE, msg.sender),
            'DiscountProcessor: caller is not a processor admin'
        );
        // Находим и удаляем подписанта из списка
        uint256 signerIndex = type(uint256).max;
        for (uint256 i = 0; i < validSigners[moduleId].length; i++) {
            if (validSigners[moduleId][i] == signer) {
                signerIndex = i;
                break;
            }
        }

        // Если подписант найден, удаляем его
        if (signerIndex != type(uint256).max) {
            // Заменяем удаляемый элемент последним и уменьшаем массив
            validSigners[moduleId][signerIndex] = validSigners[moduleId][validSigners[moduleId].length - 1];
            validSigners[moduleId].pop();

            emit ValidSignerRemoved(moduleId, signer);
        }
    }

    /**
     * @notice Рассчитать скидку для платежа
     * @param moduleId Идентификатор модуля
     * @param token Адрес токена
     * @param amount Сумма платежа
     * @return discountAmount Рассчитанная скидка
     * @return appliedRuleId Идентификатор примененного правила
     */
    function findBestDiscount(
        bytes32 moduleId,
        address token,
        uint256 amount,
        address user
    ) public view returns (uint256 discountAmount, bytes32 appliedRuleId) {
        uint256 bestDiscount = 0;
        bytes32 bestRuleId;

        // Проходим по всем правилам для модуля
        bytes32[] memory rules = moduleDiscountRules[moduleId];
        for (uint256 i = 0; i < rules.length; i++) {
            DiscountRule memory rule = discountRules[moduleId][token][rules[i]];

            // Проверяем активность правила, срок действия и минимальную сумму
            if (!rule.active || block.timestamp > rule.validUntil || amount < rule.minAmount) {
                continue;
            }

            uint256 currentDiscount = 0;

            // Рассчитываем скидку в зависимости от типа
            if (rule.discountType == DiscountType.PERCENTAGE) {
                currentDiscount = (amount * uint256(rule.percentBps)) / 10000;
            } else if (rule.discountType == DiscountType.FIXED) {
                currentDiscount = rule.fixedAmount;
                // Ограничиваем фиксированную скидку суммой платежа
                if (currentDiscount > amount) {
                    currentDiscount = amount;
                }
            }

            // Выбираем правило с наибольшей скидкой
            if (currentDiscount > bestDiscount) {
                bestDiscount = currentDiscount;
                bestRuleId = rules[i];
            }
        }

        return (bestDiscount, bestRuleId);
    }

    /**
     * @notice Получить информацию о правиле скидки
     * @param moduleId Идентификатор модуля
     * @param token Адрес токена
     * @param ruleId Идентификатор правила
     * @return discountType Тип скидки
     * @return percentBps Процент скидки
     * @return fixedAmount Фиксированная сумма
     * @return minAmount Минимальная сумма для применения
     * @return validUntil Срок действия
     * @return active Активность правила
     */
    function getDiscountRule(
        bytes32 moduleId,
        address token,
        bytes32 ruleId
    )
        external
        view
        returns (
            DiscountType discountType,
            uint16 percentBps,
            uint256 fixedAmount,
            uint256 minAmount,
            uint64 validUntil,
            bool active
        )
    {
        DiscountRule memory rule = discountRules[moduleId][token][ruleId];
        return (rule.discountType, rule.percentBps, rule.fixedAmount, rule.minAmount, rule.validUntil, rule.active);
    }

    /**
     * @notice Получить все правила скидок для модуля
     * @param moduleId Идентификатор модуля
     * @return ruleIds Массив идентификаторов правил
     */
    function getModuleDiscountRules(bytes32 moduleId) external view returns (bytes32[] memory ruleIds) {
        return moduleDiscountRules[moduleId];
    }

    /**
     * @notice Получить всех валидных подписантов для модуля
     * @param moduleId Идентификатор модуля
     * @return signers Массив адресов подписантов
     */
    function getValidSigners(bytes32 moduleId) external view returns (address[] memory signers) {
        return validSigners[moduleId];
    }

    /**
     * @notice Проверить, использована ли подпись
     * @param signatureHash Хеш подписи
     * @return used Использована ли подпись
     */
    function isSignatureUsed(bytes32 signatureHash) external view returns (bool used) {
        return usedSignatures[signatureHash];
    }

    /**
     * @notice Извлечь данные подписи из метаданных (для внешнего использования)
     * @param metadata Метаданные
     * @return signature Подпись
     * @return discountHash Хеш данных скидки
     */
    function decodeSignatureFromMetadata(
        bytes memory metadata
    ) external pure returns (bytes memory signature, bytes32 discountHash) {
        // Ожидаемый формат: [discountHash (32 bytes)][signature (variable length)]
        require(metadata.length > 32, 'DiscountProcessor: invalid metadata format');

        // Извлекаем хеш скидки (первые 32 байта)
        bytes32 hash;
        assembly {
            hash := mload(add(metadata, 32))
        }

        // Извлекаем подпись (оставшиеся байты)
        bytes memory sig = new bytes(metadata.length - 32);
        for (uint256 i = 0; i < sig.length; i++) {
            sig[i] = metadata[i + 32];
        }

        return (sig, hash);
    }

    /**
     * @notice Создать хеш для подписи скидки
     * @param moduleId Идентификатор модуля
     * @param user Адрес пользователя
     * @param discountPercent Процент скидки
     * @param validUntil Срок действия
     * @param skuOrListingId SKU или ID листинга (опционально)
     * @return Хеш для подписи
     */
    function getDiscountDigest(
        bytes32 moduleId,
        address user,
        uint16 discountPercent,
        uint64 validUntil,
        bytes32 skuOrListingId
    ) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    'Discount(bytes32 moduleId,address user,uint16 discountPercent,uint64 validUntil,bytes32 skuOrListingId)'
                ),
                moduleId,
                user,
                discountPercent,
                validUntil,
                skuOrListingId
            )
        );

        return MessageHashUtils.toTypedDataHash(DOMAIN_SEPARATOR, structHash);
    }

    /**
     * @notice Валидировать подпись скидки
     * @param discountHash Хеш данных скидки
     * @param signature Подпись
     * @param moduleId Идентификатор модуля
     * @param user Адрес пользователя
     * @return valid Валидна ли подпись
     * @return discountPercent Процент скидки
     */
    function validateDiscountSignature(
        bytes32 discountHash,
        bytes memory signature,
        bytes32 moduleId,
        address user
    ) public view returns (bool valid, uint16 discountPercent) {
        // Восстанавливаем адрес подписавшего
        address signer = ECDSA.recover(discountHash, signature);

        // Проверяем, является ли подписавший валидным для модуля
        bool isValidSigner = false;
        for (uint256 i = 0; i < validSigners[moduleId].length; i++) {
            if (validSigners[moduleId][i] == signer) {
                isValidSigner = true;
                break;
            }
        }

        if (!isValidSigner) {
            return (false, 0);
        }

        // Декодируем данные скидки из хеша (необходимо для восстановления процента скидки)
        // В реальном сценарии, возможно, потребуется другая реализация для восстановления данных
        // Здесь мы используем упрощенный подход

        // Декодируем discountPercent из хеша (в реальном приложении может быть другой подход)
        // Предполагаем формат: moduleId(32) + user(20) + discountPercent(2) + validUntil(8) + skuOrListingId(32)
        uint16 percent = uint16(uint256(discountHash) & 0xFFFF);

        // Проверяем, что процент не превышает максимально допустимый
        if (percent > MAX_DISCOUNT_BPS) {
            return (false, 0);
        }

        return (true, percent);
    }

    /**
     * @notice Создать данные скидки для подписи
     * @param moduleId Идентификатор модуля
     * @param user Адрес пользователя
     * @param discountPercent Процент скидки
     * @param validUntil Срок действия
     * @param skuOrListingId SKU или ID листинга (опционально)
     * @return Данные для подписи
     */
    function createDiscountData(
        bytes32 moduleId,
        address user,
        uint16 discountPercent,
        uint64 validUntil,
        bytes32 skuOrListingId
    ) external view returns (bytes32) {
        require(discountPercent <= MAX_DISCOUNT_BPS, 'DiscountProcessor: discount percent too high');
        require(validUntil > block.timestamp, 'DiscountProcessor: invalid expiration time');

        return getDiscountDigest(moduleId, user, discountPercent, validUntil, skuOrListingId);
    }

    /**
     * @notice Извлечь метаданные скидки из общих метаданных
     * @param metadata Метаданные контекста платежа
     * @return signatureHash Хеш подписи скидки
     * @return signatureData Данные подписи
     */
    function extractDiscountMetadata(
        bytes memory metadata
    ) external pure returns (bytes32 signatureHash, bytes memory signatureData) {
        // Пробуем распаковать как массив метаданных процессоров
        ProcessorMetadataLib.ProcessorMetadata[] memory metadataArray = ProcessorMetadataLib.unpackMetadata(metadata);

        // Ищем метаданные для процессора скидок
        (bool found, ProcessorMetadataLib.ProcessorMetadata memory discountMetadata) = ProcessorMetadataLib
            .findMetadataByType(metadataArray, ProcessorMetadataLib.ProcessorType.DISCOUNT);

        if (found) {
            // Распаковываем специфичные данные процессора скидок
            return abi.decode(discountMetadata.processorData, (bytes32, bytes));
        }

        // Если не найдены метаданные, возвращаем пустые значения
        return (bytes32(0), '');
    }
}
