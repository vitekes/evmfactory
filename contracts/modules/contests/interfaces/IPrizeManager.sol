// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../shared/PrizeInfo.sol";

/// @title IPrizeManager
/// @notice API для управления шаблонами призовых слотов в модуле конкурсов
interface IPrizeManager {
    /// @notice Добавить новый шаблон призовых слотов
    /// @param slots массив описаний призовых мест
    /// @param description текстовое описание шаблона
    /// @return templateId уникальный идентификатор созданного шаблона
    function addTemplate(
        PrizeInfo[] calldata slots,
        string calldata description
    ) external returns (uint256 templateId);

    /// @notice Обновить существующий шаблон призовых слотов
    /// @param templateId идентификатор шаблона для обновления
    /// @param slots новый массив описаний призовых мест
    /// @param description новое описание шаблона
    function updateTemplate(
        uint256 templateId,
        PrizeInfo[] calldata slots,
        string calldata description
    ) external;

    /// @notice Получить данные шаблона по его идентификатору
    /// @param templateId идентификатор искомого шаблона
    /// @return slots массив описаний призовых мест
    /// @return description текстовое описание шаблона
    function getTemplate(
        uint256 templateId
    ) external view returns (
        PrizeInfo[] memory slots,
        string memory description
    );
}
