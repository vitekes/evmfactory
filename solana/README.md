# Solana Port Prototype

Черновой Anchor-workspace для переноса функционала marketplace/подписок/конкурсов в Solana.

- `programs/evmfactory` — основная программа Anchor.
- `tests/` — интеграционные тесты (TypeScript).
- `migrations/` — скрипты деплоя Anchor.
- `client/` — вспомогательные SDK/утилиты для фронта.

⚙️ Быстрый старт:

```bash
cd solana
npm install          # устанавливает зависимости для тестов
anchor build        # компиляция программы
anchor test         # прогон интеграционных тестов
```

Файлы и код — черновые заготовки: нужно дописать трансферы, проверки подписи и интеграцию с off-chain листингами.
