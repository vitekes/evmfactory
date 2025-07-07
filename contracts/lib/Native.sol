// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title Native - Библиотека для работы с нативной валютой (ETH)
/// @notice Предоставляет утилиты для проверки и обработки нативной валюты
library Native {
    // Адрес-константа для обозначения нативной валюты в системе
    address internal constant ETH_SENTINEL = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    // Алиас для совместимости с ChainlinkPriceOracle
    address internal constant ETH_ADDRESS = ETH_SENTINEL;
    // Zero address is also used to represent native currency
    address internal constant ZERO_ADDRESS = address(0);

    /// @notice Проверяет, является ли адрес обозначением нативной валюты
    /// @param token Адрес для проверки
    /// @return Является ли адрес обозначением нативной валюты
    function isNative(address token) internal pure returns (bool) {
        return token == address(0) || token == ETH_SENTINEL;
    }

    /// @notice Отправляет нативную валюту на указанный адрес
    /// @param recipient Адрес получателя
    /// @param amount Сумма для отправки
    /// @return Успешность отправки
    function sendValue(address payable recipient, uint256 amount) internal returns (bool) {
        (bool success, ) = recipient.call{value: amount}("");
        return success;
    }
}
