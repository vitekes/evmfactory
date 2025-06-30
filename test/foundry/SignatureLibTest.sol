// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/lib/SignatureLib.sol";

contract SignatureLibTest is Test {
    bytes32 private constant _TYPE_HASH = keccak256("Plan(address merchant,address token,uint256 price,uint256 period,uint256 expiry,uint256[] chainIds,string description)");
    address private constant _TEST_MERCHANT = address(0x1234);
    address private constant _TEST_TOKEN = address(0x5678);
    
    bytes32 private _domainSeparator;
    
    function setUp() public {
        // Создаем правильный domain separator для тестов
        _domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(uint256 chainId,address verifyingContract)"),
                block.chainid,
                address(this)
            )
        );
    }
    
    function testHashPlan() public {
        // Создаем тестовый план
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = block.chainid;
        
        SignatureLib.Plan memory plan = SignatureLib.Plan({
            merchant: _TEST_MERCHANT,
            token: _TEST_TOKEN,
            price: 100,
            period: 30 days,
            expiry: block.timestamp + 365 days,
            chainIds: chainIds,
            description: "Test Plan"
        });
        
        // Хешируем план
        bytes32 structHash = keccak256(
            abi.encode(
                _TYPE_HASH,
                plan.merchant,
                plan.token,
                plan.price,
                plan.period,
                plan.expiry,
                keccak256(abi.encodePacked(plan.chainIds)),
                keccak256(bytes(plan.description))
            )
        );
        
        bytes32 expectedHash = keccak256(abi.encodePacked("\x19\x01", _domainSeparator, structHash));
        bytes32 actualHash = SignatureLib.hashPlan(plan, _domainSeparator);
        
        assertEq(actualHash, expectedHash, "Plan hash calculation is incorrect");
    }
    
    function testHashPlanWithDifferentChainIds() public {
        // Проверка с несколькими chainIds
        uint256[] memory chainIds1 = new uint256[](1);
        chainIds1[0] = 1;
        
        uint256[] memory chainIds2 = new uint256[](2);
        chainIds2[0] = 1;
        chainIds2[1] = 137;
        
        SignatureLib.Plan memory plan1 = SignatureLib.Plan({
            merchant: _TEST_MERCHANT,
            token: _TEST_TOKEN,
            price: 100,
            period: 30 days,
            expiry: block.timestamp + 365 days,
            chainIds: chainIds1,
            description: "Test Plan"
        });
        
        SignatureLib.Plan memory plan2 = SignatureLib.Plan({
            merchant: _TEST_MERCHANT,
            token: _TEST_TOKEN,
            price: 100,
            period: 30 days,
            expiry: block.timestamp + 365 days,
            chainIds: chainIds2,
            description: "Test Plan"
        });
        
        bytes32 hash1 = SignatureLib.hashPlan(plan1, _domainSeparator);
        bytes32 hash2 = SignatureLib.hashPlan(plan2, _domainSeparator);
        
        assertTrue(hash1 != hash2, "Plans with different chainIds should have different hashes");
    }
    
    function testHashPlanWithEmptyChainIds() public {
        // Проверка с пустым массивом chainIds
        uint256[] memory emptyChainIds = new uint256[](0);
        
        SignatureLib.Plan memory plan = SignatureLib.Plan({
            merchant: _TEST_MERCHANT,
            token: _TEST_TOKEN,
            price: 100,
            period: 30 days,
            expiry: block.timestamp + 365 days,
            chainIds: emptyChainIds,
            description: "Test Plan"
        });
        
        // Не должно быть ревертов
        bytes32 hash = SignatureLib.hashPlan(plan, _domainSeparator);
        assertTrue(hash != bytes32(0), "Hash should not be zero even with empty chainIds");
    }
}