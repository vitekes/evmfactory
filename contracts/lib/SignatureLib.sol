// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

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

    bytes32 internal constant LISTING_TYPEHASH = keccak256(
        "Listing(uint256[] chainIds,address token,uint256 price,bytes32 sku,address seller,uint256 salt,uint64 expiry)"
    );

    bytes32 internal constant PLAN_TYPEHASH = keccak256(
        "Plan(uint256[] chainIds,uint256 price,uint256 period,address token,address merchant,uint256 salt,uint64 expiry)"
    );

    function hashListing(Listing calldata l) internal pure returns (bytes32) {
        bytes32 chainHash = keccak256(abi.encode(l.chainIds.length, l.chainIds));
        return
            keccak256(
                abi.encode(
                    LISTING_TYPEHASH,
                    chainHash,
                    l.token,
                    l.price,
                    l.sku,
                    l.seller,
                    l.salt,
                    l.expiry
                )
            );
    }

    function hashPlan(Plan calldata p) internal pure returns (bytes32) {
        bytes32 chainHash = keccak256(abi.encode(p.chainIds.length, p.chainIds));
        return
            keccak256(
                abi.encode(
                    PLAN_TYPEHASH,
                    chainHash,
                    p.price,
                    p.period,
                    p.token,
                    p.merchant,
                    p.salt,
                    p.expiry
                )
            );
    }
}
