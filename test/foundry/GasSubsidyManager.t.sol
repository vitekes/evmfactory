// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "contracts/core/GasSubsidyManager.sol";
import "contracts/core/AccessControlCenter.sol";

contract GasSubsidyManagerTest is Test {
    GasSubsidyManager public gasManager;
    AccessControlCenter public acl;
    
    address admin = address(0x1);
    address featureOwner = address(0x2);
    address automation = address(0x3);
    address user = address(0x4);
    address relayer = address(0x5);
    
    bytes32 moduleId = keccak256("TEST_MODULE");
    address testContract = address(0x1234);
    
    function setUp() public {
        vm.startPrank(admin);
        
        // Деплоим ACL
        acl = new AccessControlCenter();
        acl.initialize(admin);
        
        // Настраиваем роли
        acl.grantRole(acl.DEFAULT_ADMIN_ROLE(), admin);
        acl.grantRole(acl.FEATURE_OWNER_ROLE(), featureOwner);
        acl.grantRole(acl.AUTOMATION_ROLE(), automation);
        
        // Деплоим GasSubsidyManager
        gasManager = new GasSubsidyManager();
        gasManager.initialize(address(acl));
        
        vm.stopPrank();
        
        // Фондируем GasSubsidyManager для тестов
        vm.deal(address(gasManager), 10 ether);
    }
    
    function testInitialize() public {
        // Проверяем, что инициализация прошла успешно
        assertEq(address(gasManager.access()), address(acl), "AccessControlCenter should be set correctly");
        
        // Повторная инициализация должна быть отклонена
        vm.expectRevert();
        gasManager.initialize(address(acl));
    }
    
    function testSetGasRefundLimit() public {
        vm.startPrank(admin);
        
        // Устанавливаем лимит
        gasManager.setGasRefundLimit(moduleId, 1 ether);
        
        // Проверяем установку
        assertEq(gasManager.gasRefundPerTx(moduleId), 1 ether, "Gas refund limit should be set correctly");
        
        vm.stopPrank();
        
        // Неадмин не может устанавливать лимит
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("NotAdmin()"));
        gasManager.setGasRefundLimit(moduleId, 2_000_000);
        vm.stopPrank();
    }
    
    function testSetEligibility() public {
        vm.startPrank(featureOwner);
        
        // Устанавливаем eligibility
        gasManager.setEligibility(moduleId, user, true);
        
        // Проверяем установку
        assertTrue(gasManager.isEligible(moduleId, user), "User should be eligible");
        
        // Отключаем eligibility
        gasManager.setEligibility(moduleId, user, false);
        assertFalse(gasManager.isEligible(moduleId, user), "User should not be eligible");
        
        vm.stopPrank();
        
        // Обычный пользователь не может устанавливать eligibility
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("NotFeatureOwner()"));
        gasManager.setEligibility(moduleId, user, true);
        vm.stopPrank();
    }
    
    function testSetGasCoverageEnabled() public {
        vm.startPrank(featureOwner);
        
        // Включаем coverage для контракта
        gasManager.setGasCoverageEnabled(moduleId, testContract, true);
        
        // Проверяем установку
        assertTrue(gasManager.gasCoverageEnabled(moduleId, testContract), "Contract should have gas coverage enabled");
        
        vm.stopPrank();
    }
    
    function testIsGasFree() public {
        vm.startPrank(featureOwner);
        
        // Настраиваем для теста
        gasManager.setEligibility(moduleId, user, true);
        gasManager.setGasCoverageEnabled(moduleId, testContract, true);
        
        vm.stopPrank();
        
        // Проверяем isGasFree
        assertTrue(gasManager.isGasFree(moduleId, user, testContract), "Should be gas free");
        
        // Если одно из условий не выполнено, то не должно быть gas free
        vm.startPrank(featureOwner);
        gasManager.setEligibility(moduleId, user, false);
        vm.stopPrank();
        
        assertFalse(gasManager.isGasFree(moduleId, user, testContract), "Should not be gas free if user not eligible");
    }
    
    function testRefundGas() public {
        vm.startPrank(admin);
        gasManager.setGasRefundLimit(moduleId, 1 ether);
        vm.stopPrank();
        
        uint256 relayerBalanceBefore = address(relayer).balance;
        
        // Выполняем refundGas от имени automation
        vm.startPrank(automation);
        vm.fee(100 gwei); // устанавливаем базовую комиссию
        vm.txGasPrice(150 gwei); // устанавливаем gas price для транзакции
        
        uint256 gasUsed = 50_000;
        uint256 priorityCap = 100 gwei;
        
        gasManager.refundGas(moduleId, payable(relayer), gasUsed, priorityCap);
        
        vm.stopPrank();
        
        // Проверяем, что relayer получил оплату
        uint256 expectedRefund = 150 gwei * gasUsed; // gas price * gasUsed
        assertEq(
            address(relayer).balance - relayerBalanceBefore, 
            expectedRefund, 
            "Relayer should receive correct refund"
        );
    }
    
    function testRefundGasEdgeCases() public {
        vm.startPrank(admin);
        gasManager.setGasRefundLimit(moduleId, 1_000_000);
        vm.stopPrank();
        
        vm.startPrank(automation);
        vm.fee(100 gwei);
        vm.txGasPrice(150 gwei);
        
        // Тест с gasUsed = 0
        vm.expectRevert(abi.encodeWithSignature("GasZero()"));
        gasManager.refundGas(moduleId, payable(relayer), 0, 100 gwei);
        
        // Тест с лимитом = 0 (если лимит был сброшен)
        vm.startPrank(admin);
        gasManager.setGasRefundLimit(moduleId, 0);
        vm.stopPrank();
        
        vm.startPrank(automation);
        vm.expectRevert(abi.encodeWithSignature("RefundDisabled()"));
        gasManager.refundGas(moduleId, payable(relayer), 50_000, 100 gwei);
        
        vm.stopPrank();
    }
    
    function testReceiveEther() public {
        uint256 initialBalance = address(gasManager).balance;
        
        // Отправляем эфир на контракт
        (bool success, ) = address(gasManager).call{value: 1 ether}("");
        assertTrue(success, "Should accept ETH");
        
        // Проверяем, что баланс увеличился
        assertEq(
            address(gasManager).balance, 
            initialBalance + 1 ether, 
            "Contract balance should increase"
        );
    }
    
    function testSetAccessControl() public {
        address newACL = address(0x9999);
        
        vm.startPrank(admin);
        // Нельзя установить нулевой адрес
        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        gasManager.setAccessControl(address(0));

        gasManager.setAccessControl(newACL);
        vm.stopPrank();

        assertEq(address(gasManager.access()), newACL, "AccessControlCenter should be updated");
    }
    
    function testAuthorizeUpgrade() public {
        address newImplementation = address(0x8888);
        
        // Проверяем, что неадмин не может обновить контракт
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("UUPSUnauthorizedCallContext()"));
        gasManager.upgradeToAndCall(newImplementation, "");
        vm.stopPrank();
        
        // Нулевой адрес не должен быть разрешен даже для админа
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSignature("UUPSUnauthorizedCallContext()"));
        gasManager.upgradeToAndCall(address(0), "");
        vm.stopPrank();
    }
}