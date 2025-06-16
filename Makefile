
# =============================================
# 🧪 УНИВЕРСАЛЬНЫЕ КОМАНДЫ ДЛЯ ТЕСТОВ
# =============================================

.PHONY: help test test-unit test-integration test-e2e test-all test-coverage test-quick test-watch clean compile

# По умолчанию показываем help
help:
	@node test/test-runner.js --help

# Основные команды тестирования  
test-unit:
	@node test/test-runner.js unit

test-integration:
	@node test/test-runner.js integration

test-e2e:
	@node test/test-runner.js e2e

test-all:
	@node test/test-runner.js all

test-coverage:
	@node test/test-runner.js coverage

test-quick:
	@node test/test-runner.js quick

test-watch:
	@npm run test:watch

# Утилитарные команды
compile:
	@npm run compile

clean:
	@npm run clean

# Алиасы для краткости
test: test-unit
coverage: test-coverage
quick: test-quick
watch: test-watch