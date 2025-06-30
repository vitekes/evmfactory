// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "contracts/lib/SignatureLib.sol";

contract SignatureLibWrapper {
    function hashPlan(SignatureLib.Plan calldata plan, bytes32 ds) external pure returns (bytes32) {
        return SignatureLib.hashPlan(plan, ds);
    }
}

using SignatureLib for SignatureLib.Plan;

contract SignatureLibTest is Test {
    bytes32 private constant _TYPE_HASH = keccak256(
        "Plan(uint256[] chainIds,uint256 price,uint256 period,address token,address merchant,uint256 salt,uint64 expiry)"
    );
    address private constant _TEST_MERCHANT = address(0x1234);
    address private constant _TEST_TOKEN = address(0x5678);
    
    bytes32 private _domainSeparator;
    SignatureLibWrapper private wrapper;
    
    function setUp() public {
        // Создаем правильный domain separator для тестов
        _domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(uint256 chainId,address verifyingContract)"),
                block.chainid,
                address(this)
            )
        );
        wrapper = new SignatureLibWrapper();
    }
    
    function testHashPlan() public {
        // Создаем тестовый план
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = block.chainid;
        
        SignatureLib.Plan memory plan = SignatureLib.Plan({
            chainIds: chainIds,
            price: 100,
            period: 30 days,
            token: _TEST_TOKEN,
            merchant: _TEST_MERCHANT,
            salt: 0,
            expiry: uint64(block.timestamp + 365 days)
        });
        
        // Хешируем план
        bytes32 structHash = keccak256(
            abi.encode(
                _TYPE_HASH,
                keccak256(abi.encodePacked(plan.chainIds)),
                plan.price,
                plan.period,
                plan.token,
                plan.merchant,
                plan.salt,
                plan.expiry
            )
        );
        
        bytes32 expectedHash = keccak256(abi.encodePacked("\x19\x01", _domainSeparator, structHash));
        bytes32 actualHash = wrapper.hashPlan(plan, _domainSeparator);
        
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
            chainIds: chainIds1,
            price: 100,
            period: 30 days,
            token: _TEST_TOKEN,
            merchant: _TEST_MERCHANT,
            salt: 0,
            expiry: uint64(block.timestamp + 365 days)
        });
        
        SignatureLib.Plan memory plan2 = SignatureLib.Plan({
            chainIds: chainIds2,
            price: 100,
            period: 30 days,
            token: _TEST_TOKEN,
            merchant: _TEST_MERCHANT,
            salt: 0,
            expiry: uint64(block.timestamp + 365 days)
        });
        
        bytes32 hash1 = wrapper.hashPlan(plan1, _domainSeparator);
        bytes32 hash2 = wrapper.hashPlan(plan2, _domainSeparator);
        
        assertTrue(hash1 != hash2, "Plans with different chainIds should have different hashes");
    }
    
    function testHashPlanWithEmptyChainIds() public {
        // Проверка с пустым массивом chainIds
        uint256[] memory emptyChainIds = new uint256[](0);
        
        SignatureLib.Plan memory plan = SignatureLib.Plan({
            chainIds: emptyChainIds,
            price: 100,
            period: 30 days,
            token: _TEST_TOKEN,
            merchant: _TEST_MERCHANT,
            salt: 0,
            expiry: uint64(block.timestamp + 365 days)
        });
        
        // Не должно быть ревертов
        bytes32 hash = wrapper.hashPlan(plan, _domainSeparator);
        assertTrue(hash != bytes32(0), "Hash should not be zero even with empty chainIds");
    }
}