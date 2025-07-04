// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../core/MultiValidator.sol";

/// @title MockMultiValidatorWithEvents
/// @notice MultiValidator с дублирующими событиями для сравнения расхода газа
/// @dev Эта версия эмитирует как локальные события, так и отправляет их через EventRouter
contract MockMultiValidatorWithEvents is MultiValidator {
    // Дополнительное дублирующее событие
    event TokenAllowed(address indexed token, bool status);

    // Переопределяем функцию для эмиссии дополнительного события
    function _emitTokenEvent(address token, bool status) internal override {
        // Эмитируем дублирующее событие
        emit TokenAllowed(token, status);

        // Вызываем оригинальную реализацию для отправки через EventRouter
        super._emitTokenEvent(token, status);
    }
}
