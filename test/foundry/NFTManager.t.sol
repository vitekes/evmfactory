// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "contracts/core/EventRouter.sol";
import "contracts/core/AccessControlCenter.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract EventRouterTest is Test {
    EventRouter public router;
    AccessControlCenter public acl;
    
    address admin = address(0x1);
    address module = address(0x2);
    address user = address(0x3);
    
    event EventRouted(EventRouter.EventKind indexed kind, bytes payload);
    
    function setUp() public {
        vm.startPrank(admin);
        
        // Деплоим ACL
        AccessControlCenter accImpl = new AccessControlCenter();
        bytes memory accData = abi.encodeCall(AccessControlCenter.initialize, admin);
        ERC1967Proxy accProxy = new ERC1967Proxy(address(accImpl), accData);
        acl = AccessControlCenter(address(accProxy));
        
        // Настраиваем роли
        acl.grantRole(acl.DEFAULT_ADMIN_ROLE(), admin);
        acl.grantRole(acl.MODULE_ROLE(), module);
        
        // Деплоим и инициализируем EventRouter
        EventRouter impl = new EventRouter();
        bytes memory data = abi.encodeCall(EventRouter.initialize, address(acl));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        router = EventRouter(address(proxy));
        
        vm.stopPrank();
    }
    
    function testInitialize() public {
        // Проверяем, что инициализация прошла успешно
        assertEq(address(router.access()), address(acl), "AccessControlCenter should be set correctly");
        
        // Повторная инициализация должна быть отклонена
        vm.expectRevert();
        router.initialize(address(acl));
    }
    
    function testRouteEventByModule() public {
        vm.startPrank(module);
        
        bytes memory testPayload = abi.encode("test data");
        
        // Проверяем эмиссию события
        vm.expectEmit(true, false, false, true);
        emit EventRouted(EventRouter.EventKind.ContestFinalized, testPayload);
        
        router.route(EventRouter.EventKind.ContestFinalized, testPayload);
        
        vm.stopPrank();
    }
    
    function testRouteInvalidKind() public {
        vm.startPrank(module);
        
        // EventKind.Unknown (0) не должно быть разрешено
        vm.expectRevert(abi.encodeWithSignature("InvalidKind()"));
        router.route(EventRouter.EventKind.Unknown, "");
        
        vm.stopPrank();
    }
    
    function testRouteNotModule() public {
        vm.startPrank(user);
        
        // Обычный пользователь не должен иметь доступ к route
        vm.expectRevert(abi.encodeWithSignature("NotModule()"));
        router.route(EventRouter.EventKind.ContestFinalized, "");
        
        vm.stopPrank();
    }
    
    function testAuthorizeUpgrade() public {
        address newImplementation = address(0x8888);
        
        // Проверяем, что неадмин не может обновить контракт
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("NotAdmin()"));
        router.upgradeToAndCall(newImplementation, "");
        vm.stopPrank();
        
        // Нулевой адрес не должен быть разрешен даже для админа
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSignature("InvalidImplementation()"));
        router.upgradeToAndCall(address(0), "");
        vm.stopPrank();
    }
    
    function testRouteAllEventKinds() public {
        vm.startPrank(module);
        
        // Проверяем маршрутизацию для каждого типа события
        router.route(EventRouter.EventKind.ListingCreated, "");
        router.route(EventRouter.EventKind.SubscriptionCharged, "");
        router.route(EventRouter.EventKind.ContestFinalized, "");
        
        // Все вызовы должны пройти без ошибок
        
        vm.stopPrank();
    }
    
    function testRouteWithLargePayload() public {
        vm.startPrank(module);
        
        // Создаем большой объем данных
        bytes memory largePayload = new bytes(10000);
        for (uint i = 0; i < 10000; i++) {
            largePayload[i] = 0x42;
        }
        
        // Должен успешно маршрутизировать большой объем данных
        router.route(EventRouter.EventKind.ContestFinalized, largePayload);
        
        vm.stopPrank();
    }
}