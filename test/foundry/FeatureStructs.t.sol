// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../contracts/interfaces/IEventPayload.sol";

contract FeatureStructsTest is Test {
    function testFeatureEventStruct() public pure {
        // Проверяем, что структура FeatureEvent корректно определена
        IEventPayload.FeatureEvent memory featureEvent = IEventPayload.FeatureEvent({
            featureId: bytes32(uint256(1)),
            oldImplementation: address(0x1),
            newImplementation: address(0x2),
            context: 1,
            version: 1
        });

        // Простая проверка, чтобы убедиться, что тест компилируется
        bytes32 id = featureEvent.featureId;
        address oldImpl = featureEvent.oldImplementation;
        address newImpl = featureEvent.newImplementation;
        uint8 context = featureEvent.context;
        uint16 version = featureEvent.version;

        // Проверка, что значения правильно присвоены
        assert(id == bytes32(uint256(1)));
        assert(oldImpl == address(0x1));
        assert(newImpl == address(0x2));
        assert(context == 1);
        assert(version == 1);
    }

    function testTokenEventStruct() public pure {
        // Проверяем структуру TokenEvent
        IEventPayload.TokenEvent memory tokenEvent = IEventPayload.TokenEvent({
            tokenAddress: address(0x1),
            fromToken: address(0),
            toToken: address(0),
            amount: 100,
            convertedAmount: 0,
            version: 1
        });

        // Проверяем присвоенные значения
        assert(tokenEvent.tokenAddress == address(0x1));
        assert(tokenEvent.amount == 100);
    }

    function testMarketplaceEventStruct() public pure {
        // Проверяем структуру MarketplaceEvent
        IEventPayload.MarketplaceEvent memory marketEvent = IEventPayload.MarketplaceEvent({
            sku: bytes32(uint256(1)),
            seller: address(0x1),
            buyer: address(0x2),
            price: 100,
            paymentToken: address(0x3),
            paymentAmount: 100,
            timestamp: 1000,
            listingHash: bytes32(uint256(2)),
            version: 1
        });

        // Проверяем присвоенные значения
        assert(marketEvent.sku == bytes32(uint256(1)));
        assert(marketEvent.price == 100);
    }
}
