# Architecture and data

`flutter/lib` contains the Material 3 application, controllers and platform adapters. `flutter/rust/core` owns validation, recipes, SQLite storage, shopping arithmetic, ZIP backups, snapshots and LAN sync. `flutter/rust/bridge` exposes the typed flutter_rust_bridge API. Generated bindings are committed; the test-only `probe` crate never ships in app packages.

Android Kotlin adapters provide local platform integrations, permissions, secure storage and sharing. Windows C++ adapters provide desktop integration and HTTP imports. ZXing decodes QR invitations locally. Tests use generated recipes, mock services and loopback servers; no Gemini key is required.

## Interchange

Current recipe schema and SQLite layout are version 2; sync protocol is 4. Recipe IDs survive backup, restore and sync. ZIPs contain per-recipe JSON and optional local shopping category setup. Schema 1 and schema 2 backups remain readable. Snapshots use the same ZIP format. Shopping rows and credentials are not included in recipe backups. Shared recipes use readable Text v1; earlier text exports still import.

The immutable synthetic fixtures in `flutter/rust/core/tests/fixtures/compatibility` exercise every released format. The core validator is the authority for all recipe ingress. Database files are local and must never be copied between running apps as a sync mechanism.

## Sync and identity

Devices pair using a one-use invitation and exchange permanent credentials inside an encrypted Noise session. Paired devices may change and delete recipes. Conflicts and deletions propagate through recipe-level sync. Sync is foreground-only on Android and runs while the Windows app is open, including minimized. Protocol mismatches refuse sync and require an update; stored recipes remain intact.

Production uses `com.sylph.cookdex` and port 47831. Dev uses `com.sylph.cookdex.dev` and port 47832, with distinct authenticated domains and local data. Profiling uses the permanent separate `com.sylph.cookdex.dev.profile` identity. The build wrapper selects native identity, Dart identity and Rust sync features together.
