// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../contracts/core/MultiValidator.sol";
import "../../contracts/core/Registry.sol";
import "../../contracts/core/AccessControlCenter.sol";
import "../../contracts/interfaces/IEventRouter.sol";
import "../../contracts/interfaces/IEventPayload.sol";

/// @title MockEventRouter
/// @notice Простая реализация EventRouter для тестирования
contract MockEventRouter is IEventRouter {
    event EventRouted(EventKind indexed kind, bytes data);

    function route(EventKind kind, bytes calldata data) external override {
        emit EventRouted(kind, data);
    }
}

/// @title MockMultiValidatorWithEvents
/// @notice MultiValidator с дублирующими событиями для сравнения газа
contract MockMultiValidatorWithEvents is MultiValidator {
    // Дополнительное дублирующее событие
    event TokenAllowed(address indexed token, bool status);

    // Переопределяем функцию для эмиссии дополнительного события
    function _emitTokenEvent(address token, bool status) internal override {
        // Эмитируем дублирующее событие
        emit TokenAllowed(token, status);

        // Вызываем оригинальную реализацию для отправки через EventRouter
        super._emitTokenEvent(token, status);
    }
}

contract GasOptimizationTest is Test {
    AccessControlCenter public accessControl;
    Registry public registry;
    MockEventRouter public eventRouter;
    MultiValidator public optimizedValidator;
    MockMultiValidatorWithEvents public legacyValidator;

    address public admin;
    address public governor;

    function setUp() public {
        admin = makeAddr("admin");
        governor = makeAddr("governor");

        // Создаем контракты
        eventRouter = new MockEventRouter();

        accessControl = new AccessControlCenter();
        accessControl.initialize(admin, address(0));

        registry = new Registry();
        registry.initialize(address(accessControl));

        // Связываем контракты
        accessControl.setRegistry(address(registry));

        // Регистрируем EventRouter
        vm.startPrank(admin);
        registry.setCoreService(CoreDefs.SERVICE_EVENT_ROUTER, address(eventRouter));

        // Назначаем роли
        bytes32[] memory roles = new bytes32[](2);
        roles[0] = accessControl.GOVERNOR_ROLE();
        roles[1] = accessControl.FEATURE_OWNER_ROLE();
        accessControl.grantMultipleRoles(governor, roles);
        vm.stopPrank();

        // Создаем оптимизированный валидатор
        optimizedValidator = new MultiValidator();
        optimizedValidator.initialize(address(accessControl), address(registry));

        // Создаем валидатор с дублирующими событиями
        legacyValidator = new MockMultiValidatorWithEvents();
        legacyValidator.initialize(address(accessControl), address(registry));
    }

    function test_GasComparison_AddSingleToken() public {
        address token = makeAddr("token");

        // Тестирование оптимизированной версии
        vm.prank(governor);
        uint256 gasBefore = gasleft();
        optimizedValidator.addToken(token);
        uint256 optimizedGasUsed = gasBefore - gasleft();

        // Тестирование legacy версии с дублирующими событиями
        vm.prank(governor);
        gasBefore = gasleft();
        legacyValidator.addToken(token);
        uint256 legacyGasUsed = gasBefore - gasleft();

        // Выводим результаты
        console.log("Добавление одного токена:");
        console.log("Оптимизированная версия:", optimizedGasUsed, "газа");
        console.log("Legacy версия:", legacyGasUsed, "газа");
        console.log("Экономия:", legacyGasUsed - optimizedGasUsed, "газа");

        // Проверяем, что оптимизированная версия использует меньше газа
        assertTrue(optimizedGasUsed < legacyGasUsed, "Оптимизированная версия должна использовать меньше газа");
    }

    function test_GasComparison_BulkAddTokens() public {
        address[] memory tokens = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            tokens[i] = makeAddr(string(abi.encodePacked("token", i)));
        }

        // Тестирование оптимизированной версии
        vm.prank(governor);
        uint256 gasBefore = gasleft();
        optimizedValidator.bulkSetToken(tokens, true);
        uint256 optimizedGasUsed = gasBefore - gasleft();

        // Тестирование legacy версии
        vm.prank(governor);
        gasBefore = gasleft();
        legacyValidator.bulkSetToken(tokens, true);
        uint256 legacyGasUsed = gasBefore - gasleft();

        // Выводим результаты
        console.log("Массовое добавление токенов (5 токенов):");
        console.log("Оптимизированная версия:", optimizedGasUsed, "газа");
        console.log("Legacy версия:", legacyGasUsed, "газа");
        console.log("Экономия:", legacyGasUsed - optimizedGasUsed, "газа");
        console.log("Экономия на токен:", (legacyGasUsed - optimizedGasUsed) / 5, "газа");

        // Проверяем, что оптимизированная версия использует меньше газа
        assertTrue(optimizedGasUsed < legacyGasUsed, "Оптимизированная версия должна использовать меньше газа");
    }

    function test_GasComparison_Registry_RegisterFeature() public {
        bytes32 featureId = keccak256("TestFeature");
        address implementation = makeAddr("implementation");

        // Измеряем расход газа для регистрации фичи
        vm.prank(governor);
        uint256 gasBefore = gasleft();
        registry.registerFeature(featureId, implementation, 1);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Регистрация фичи:", gasUsed, "газа");
    }
}
