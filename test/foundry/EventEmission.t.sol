// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../contracts/core/MultiValidator.sol";
import "../../contracts/test/MockMultiValidatorWithEvents.sol";
import "../../contracts/core/Registry.sol";
import "../../contracts/core/EventRouter.sol";
import "../../contracts/core/AccessControlCenter.sol";

contract EventEmissionTest is Test {
    AccessControlCenter public accessControl;
    Registry public registry;
    EventRouter public eventRouter;
    MultiValidator public validator;
    MockMultiValidatorWithEvents public validatorWithDuplicates;

    address public admin;
    address public governor;
    address public testToken;

    event EventRouted(IEventRouter.EventKind indexed kind, bytes data);
    event TokenAllowed(address indexed token, bool status);

    function setUp() public {
        admin = makeAddr("admin");
        governor = makeAddr("governor");
        testToken = makeAddr("testToken");

        // Создаем контракты
        accessControl = new AccessControlCenter();
        accessControl.initialize(admin, address(0));

        registry = new Registry();
        registry.initialize(address(accessControl));

        eventRouter = new EventRouter();
        eventRouter.initialize(address(accessControl));

        // Связываем контракты
        accessControl.setRegistry(address(registry));
        registry.setCoreService(CoreDefs.SERVICE_EVENT_ROUTER, address(eventRouter));
        registry.setCoreService(CoreDefs.SERVICE_ACCESS_CONTROL, address(accessControl));

        // Назначаем роли
        vm.startPrank(admin);
        bytes32[] memory roles = new bytes32[](2);
        roles[0] = accessControl.GOVERNOR_ROLE();
        roles[1] = accessControl.MODULE_ROLE();
        accessControl.grantMultipleRoles(governor, roles);
        accessControl.grantRole(accessControl.MODULE_ROLE(), address(this));
        vm.stopPrank();

        // Создаем валидаторы
        validator = new MultiValidator();
        validator.initialize(address(accessControl), address(registry));

        validatorWithDuplicates = new MockMultiValidatorWithEvents();
        validatorWithDuplicates.initialize(address(accessControl), address(registry));
    }

    function testOptimizedValidatorEmitsOnlyRouterEvents() public {
        vm.startPrank(governor);

        // Проверяем, что оптимизированный валидатор не эмитирует локальные события
        vm.expectEmit(true, false, false, false);
        emit EventRouted(IEventRouter.EventKind.TokenAllowed, "");

        // Не должно быть события TokenAllowed
        validator.addToken(testToken);

        vm.stopPrank();
    }

    function testLegacyValidatorEmitsBothEvents() public {
        vm.startPrank(governor);

        // Проверяем, что legacy валидатор эмитирует оба события
        vm.expectEmit(true, true, false, false);
        emit TokenAllowed(testToken, true);

        vm.expectEmit(true, false, false, false);
        emit EventRouted(IEventRouter.EventKind.TokenAllowed, "");

        validatorWithDuplicates.addToken(testToken);

        vm.stopPrank();
    }
}
