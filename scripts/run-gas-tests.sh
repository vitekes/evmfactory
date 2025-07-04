#!/bin/bash

# Запуск тестов оптимизации газа с использованием Foundry

echo "Запуск тестов оптимизации газа..."

# Компилируем контракты
forge build --sizes

# Запускаем тесты с выводом подробной информации о расходе газа
forge test --match-path "test/foundry/GasOptimization.t.sol" -vv

echo "Тесты завершены."
