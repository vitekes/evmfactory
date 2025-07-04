// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../contracts/core/MultiValidator.sol";
import "../../contracts/test/MockMultiValidatorWithEvents.sol";
import "../../contracts/core/Registry.sol";
import "../../contracts/core/EventRouter.sol";
import "../../contracts/core/AccessControlCenter.sol";
import "../../contracts/interfaces/IEventPayload.sol";
import "../../contracts/interfaces/IEventRouter.sol";

contract MockERC20 {
    function approve(address spender, uint256 amount) public returns (bool) { return true; }
    function transferFrom(address from, address to, uint256 amount) public returns (bool) { return true; }
    function allowance(address owner, address spender) public view returns (uint256) { return 0; }
    function balanceOf(address account) public view returns (uint256) { return 0; }
}

contract EmissionOptimizationTest is Test {
    AccessControlCenter public accessControl;
    Registry public registry;
    EventRouter public eventRouter;
    MultiValidator public validator;
    MockMultiValidatorWithEvents public validatorWithEvents;

    address public admin;
    address public governor;
    address public token1;
    address public token2;

    function setUp() public {
        admin = makeAddr("admin");
        governor = makeAddr("governor");

        // Создаем контракты
        accessControl = new AccessControlCenter();
        accessControl.initialize(admin, address(0));

        registry = new Registry();
        registry.initialize(address(accessControl));

        eventRouter = new EventRouter();
        eventRouter.initialize(address(accessControl));

        // Связываем контракты
        vm.startPrank(admin);
        accessControl.setRegistry(address(registry));
        registry.setCoreService(CoreDefs.SERVICE_EVENT_ROUTER, address(eventRouter));
        registry.setCoreService(CoreDefs.SERVICE_ACCESS_CONTROL, address(accessControl));

        // Назначаем роли
        bytes32[] memory roles = new bytes32[](2);
        roles[0] = accessControl.GOVERNOR_ROLE();
        roles[1] = accessControl.MODULE_ROLE();
        accessControl.grantMultipleRoles(governor, roles);
        accessControl.grantRole(accessControl.MODULE_ROLE(), address(this));
        accessControl.grantRole(accessControl.MODULE_ROLE(), address(eventRouter));
        vm.stopPrank();

        // Создаем валидаторы
        validator = new MultiValidator();
        validator.initialize(address(accessControl), address(registry));

        validatorWithEvents = new MockMultiValidatorWithEvents();
        validatorWithEvents.initialize(address(accessControl), address(registry));

        // Создаем тестовые токены
        token1 = address(new MockERC20());
        token2 = address(new MockERC20());
    }

    function test_CompareGasUsage_AddToken() public {
        vm.startPrank(governor);

        // Тестируем оптимизированную версию
        uint256 gasBefore = gasleft();
        validator.addToken(token1);
        uint256 optimizedGas = gasBefore - gasleft();

        // Тестируем версию с дублирующими событиями
        gasBefore = gasleft();
        validatorWithEvents.addToken(token2);
        uint256 legacyGas = gasBefore - gasleft();

        console.log("Добавление токена:");
        console.log("  Оптимизировано:", optimizedGas);
        console.log("  С дублирующими событиями:", legacyGas);
        console.log("  Экономия:", legacyGas - optimizedGas, "газа");
        console.log("  Экономия: ~%", ((legacyGas - optimizedGas) * 100) / legacyGas, "%");

        assertTrue(optimizedGas < legacyGas, "Оптимизированная версия должна тратить меньше газа");
        vm.stopPrank();
    }

    function test_CompareGasUsage_BulkSetTokens() public {
        vm.startPrank(governor);

        // Подготавливаем массив токенов
        address[] memory tokens = new address[](5);
        for (uint i = 0; i < 5; i++) {
            tokens[i] = makeAddr(string(abi.encodePacked("token", i)));
        }

        // Тестируем оптимизированную версию
        uint256 gasBefore = gasleft();
        validator.bulkSetToken(tokens, true);
        uint256 optimizedGas = gasBefore - gasleft();

        // Тестируем версию с дублирующими событиями
        gasBefore = gasleft();
        validatorWithEvents.bulkSetToken(tokens, true);
        uint256 legacyGas = gasBefore - gasleft();

        console.log("Массовое добавление токенов (5):");
        console.log("  Оптимизировано:", optimizedGas);
        console.log("  С дублирующими событиями:", legacyGas);
        console.log("  Экономия:", legacyGas - optimizedGas, "газа");
        console.log("  Экономия на токен:", (legacyGas - optimizedGas) / 5, "газа");
        console.log("  Экономия: ~%", ((legacyGas - optimizedGas) * 100) / legacyGas, "%");

        assertTrue(optimizedGas < legacyGas, "Оптимизированная версия должна тратить меньше газа");
        vm.stopPrank();
    }
}
