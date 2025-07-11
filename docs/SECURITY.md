# Безопасность проекта

## Статический анализ с Slither

Для запуска статического анализа используйте следующие команды:

```bash
# Проверка только критичных уязвимостей (исключая моки)
scripts/security/run-slither.sh --critical-only

# Проверка всех уязвимостей (исключая моки)
scripts/security/run-slither.sh

# Проверка всех контрактов, включая моки
scripts/security/run-slither.sh --include-mocks
```

## Настройка конфигурации

Конфигурация Slither находится в файле `.slither.config.json`. Вы можете настроить следующие параметры:

- `filter_paths`: Строка с регулярными выражениями, разделёнными запятыми, для фильтрации путей к анализируемым файлам
- `detectors_to_exclude`: Список детекторов, которые следует исключить из анализа
- `exclude_informational`: Исключить ли информационные предупреждения

Для исключения конкретных файлов используйте `.slitherignore`.
Каталог `contracts/mocks/` уже указан в этом файле и не участвует в анализе по умолчанию.
