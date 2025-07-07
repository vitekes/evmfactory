// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';

/// @title SignatureLib - Библиотека для работы с EIP-712 подписями
/// @notice Предоставляет функции для хеширования сообщений в соответствии с EIP-712
library SignatureLib {
    struct Listing {
        uint256[] chainIds;
        address token;
        uint256 price;
        bytes32 sku;
        address seller;
        uint256 salt;
        uint64 expiry;
    }

    struct Plan {
        uint256[] chainIds;
        uint256 price;
        uint256 period;
        address token;
        address merchant;
        uint256 salt;
        uint64 expiry;
    }

    // Типы для подписей
    bytes32 internal constant LISTING_TYPEHASH =
        keccak256(
            'Listing(uint256[] chainIds,address token,uint256 price,bytes32 sku,address seller,uint256 salt,uint64 expiry)'
        );

    bytes32 internal constant PLAN_TYPEHASH =
        keccak256(
            'Plan(uint256[] chainIds,uint256 price,uint256 period,address token,address merchant,uint256 salt,uint64 expiry)'
        );

    bytes32 internal constant PROCESS_TYPEHASH =
        keccak256(
            'ProcessPayment(address payer,bytes32 moduleId,address token,uint256 amount,uint256 nonce,uint256 chainId)'
        );

    function _hashTypedDataV4(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked('\x19\x01', domainSeparator, structHash));
    }

    function hashListing(Listing calldata l) internal pure returns (bytes32) {
        bytes32 chainHash = keccak256(abi.encodePacked(l.chainIds));
        return keccak256(abi.encode(LISTING_TYPEHASH, chainHash, l.token, l.price, l.sku, l.seller, l.salt, l.expiry));
    }

    function hashListing(Listing calldata l, bytes32 domainSeparator) internal pure returns (bytes32) {
        return _hashTypedDataV4(domainSeparator, hashListing(l));
    }

    function hashPlan(Plan calldata p) internal pure returns (bytes32) {
        bytes32 chainHash = keccak256(abi.encodePacked(p.chainIds));
        return
            keccak256(abi.encode(PLAN_TYPEHASH, chainHash, p.price, p.period, p.token, p.merchant, p.salt, p.expiry));
    }

    function hashPlan(Plan calldata p, bytes32 domainSeparator) internal pure returns (bytes32) {
        return _hashTypedDataV4(domainSeparator, hashPlan(p));
    }

    /// @notice Хеширует данные для подписи платежа
    /// @param domainSeparator Разделитель домена для EIP-712
    /// @param payer Адрес плательщика
    /// @param moduleId Идентификатор модуля
    /// @param token Адрес токена
    /// @param amount Сумма платежа
    /// @param nonce Одноразовое число для предотвращения повторного использования подписи
    /// @param chainId Идентификатор сети
    /// @return Хеш данных платежа для подписи
    function hashProcessPayment(
        bytes32 domainSeparator,
        address payer,
        bytes32 moduleId,
        address token,
        uint256 amount,
        uint256 nonce,
        uint256 chainId
    ) internal pure returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(PROCESS_TYPEHASH, payer, moduleId, token, amount, nonce, chainId));
        return _hashTypedDataV4(domainSeparator, structHash);
    }

    /// @notice Восстанавливает адрес подписавшего из подписи
    /// @param hash Хеш подписанных данных
    /// @param signature Подпись
    /// @return Адрес подписавшего
    function recoverSigner(bytes32 hash, bytes memory signature) internal pure returns (address) {
        return ECDSA.recover(hash, signature);
    }
}
