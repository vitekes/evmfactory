// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Тип приза: монетарный (ERC-20) или промо (офлайн-код)
    enum PrizeType { MONETARY, PROMO }

/// @notice Описание одного призового места в конкурсе
    struct PrizeInfo {
        PrizeType prizeType;    // тип приза
        address   token;        // адрес ERC-20-токена (для MONETARY)
        uint256   amount;       // сумма токенов (для MONETARY)
        uint8     distribution; // схема распределения (0 = равномерно, 1 = нисходяще)
    }
