#!/bin/bash

CRITICAL_ONLY=false
INCLUDE_MOCKS=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --critical-only)
      CRITICAL_ONLY=true
      shift
      ;;
    --include-mocks)
      INCLUDE_MOCKS=true
      shift
      ;;
    *)
      echo "Неизвестная опция: $1"
      exit 1
      ;;
  esac
done

if [ "$CRITICAL_ONLY" = true ]; then
  echo "Проверка только критичных уязвимостей..."
  SEVERITY="--fail-high"
else
  echo "Проверка всех уязвимостей..."
  SEVERITY=""
fi

if [ "$INCLUDE_MOCKS" = true ]; then
  echo "Включая мок-контракты..."
  CONFIG=""
else
  echo "Исключая мок-контракты..."
  CONFIG="--config-file .slither.config.json"
fi

~/.local/bin/slither . $SEVERITY $CONFIG
