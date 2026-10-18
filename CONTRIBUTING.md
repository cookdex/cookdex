# Contributing

Open an issue to discuss a bug or proposed change, then submit a focused pull request with tests. Use synthetic recipes and disposable app data. Never add credentials, personal backups, device identifiers, machine paths, or generated build output.

Start with [Development](docs/DEVELOPMENT.md) and [Architecture](docs/ARCHITECTURE.md). Android touch layouts are primary; check small phones, enlarged text, and tablet landscape when changing screens. Preserve 48dp touch targets, accessible contrast, and keyboard/back navigation.

All recipe input goes through the canonical Rust validator. Keep recipe IDs, earlier backup formats and shared text readable. Test every released-format fixture; never regenerate those fixtures from the current writer during tests. Changes to pairing or sync must fail safely on incompatible versions without changing stored recipes.

Update `flutter/lib/help_content.dart` with user-visible behavior changes. Run the host suite and relevant platform checks. Automated tests use mocks and must not call Gemini. Production signing belongs to the maintainer; contributors build the separate dev identity with a standard debug key.
