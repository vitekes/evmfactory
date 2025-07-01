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

SLITHER_BIN="$(command -v slither || true)"
if [ -z "$SLITHER_BIN" ]; then
  echo "Slither not found in PATH" >&2
  exit 1
fi
$SLITHER_BIN . $SEVERITY $CONFIG
