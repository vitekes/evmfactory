// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/shared/AccessManaged.sol";
import "../contracts/core/AccessControlCenter.sol";

// Мок-контракт для тестирования AccessManaged
contract MockAccessManaged is AccessManaged {
    constructor(address accessControl) AccessManaged(accessControl) {}
    
    function doSomethingWithRole(bytes32 role) external onlyRole(role) returns (bool) {
        return true;
    }
    
    function getAcc() external view returns (address) {
        return _ACC;
    }
}

contract AccessManagedTest is Test {
    AccessControlCenter public acl;
    MockAccessManaged public managed;
    
    address admin = address(0x1);
    address user = address(0x2);
    bytes32 ROLE_A = keccak256("ROLE_A");
    
    function setUp() public {
        vm.startPrank(admin);
        
        // Деплоим ACL
        acl = new AccessControlCenter();
        acl.initialize();
        
        // Даем админу роль DEFAULT_ADMIN_ROLE
        bytes32 adminRole = acl.DEFAULT_ADMIN_ROLE();
        acl.grantRole(adminRole, admin);
        
        // Создаем тестовую роль
        acl.grantRole(ROLE_A, admin);
        
        // Деплоим контракт, использующий ACL
        managed = new MockAccessManaged(address(acl));
        
        vm.stopPrank();
    }
    
    function testOnlyRoleModifier() public {
        vm.startPrank(admin);
        
        // Админ имеет роль ROLE_A, должно выполниться успешно
        bool result = managed.doSomethingWithRole(ROLE_A);
        assertTrue(result, "Function should succeed when caller has the role");
        
        vm.stopPrank();
    }
    
    function testAccessDenied() public {
        vm.startPrank(user);
        
        // Обычный пользователь не имеет роли ROLE_A, должен быть реверт
        vm.expectRevert(abi.encodeWithSignature("Forbidden()"));
        managed.doSomethingWithRole(ROLE_A);
        
        vm.stopPrank();
    }
    
    function testRoleCheck() public {
        vm.startPrank(admin);
        
        // Тестируем проверку роли
        bool hasRole = managed.hasRole(ROLE_A, admin);
        assertTrue(hasRole, "Admin should have ROLE_A");
        
        bool userHasRole = managed.hasRole(ROLE_A, user);
        assertFalse(userHasRole, "User should not have ROLE_A");
        
        vm.stopPrank();
    }
    
    function testAccAddressStorage() public {
        // Проверяем, что _ACC правильно хранится в контракте
        address storedAcc = managed.getAcc();
        assertEq(storedAcc, address(acl), "ACC address should be stored correctly");
    }
    
    function testOnlyRoleWithNonExistentRole() public {
        vm.startPrank(admin);
        
        bytes32 nonExistentRole = keccak256("NON_EXISTENT_ROLE");
        
        // Даже админ не должен иметь доступ к несуществующей роли
        vm.expectRevert(abi.encodeWithSignature("Forbidden()"));
        managed.doSomethingWithRole(nonExistentRole);
        
        vm.stopPrank();
    }
}
