# Third-party notices

cookdex's own source is MIT-licensed. The following bundled source assets retain their upstream licenses.

## Material Symbols artwork

The launcher icons and splash image are derived from the Material Symbols outlined skillet glyph. The Android adaptive foreground and production monochrome resources preserve the original quadratic font outline with a uniform transform. `flutter/tool/preview_android_icons.cjs` renders their host previews and all legacy Android fallbacks. The Windows icon and splash image use cookdex colors, shape and wordmark from `flutter/tool/generate_branding.dart`; the Android splash pan is optically centered above its wordmark.

Copyright 2023 Google (material symbols icon fonts) and Tim Maffett (part package code).

Licensed under the Apache License, Version 2.0. See [the complete supplied license and notice](licenses/Material-Symbols-Apache-2.0.txt). Upstream: [Material Symbols](https://github.com/google/material-design-icons) and [material_symbols_icons](https://pub.dev/packages/material_symbols_icons).

## Flutter template assets and native runner code

The default development launcher icons and Flutter-generated native runner scaffolding come from Flutter. Copyright 2014 The Flutter Authors. All rights reserved. See [the complete Flutter BSD license](licenses/Flutter-BSD.txt). Flutter's [brand policy](https://flutter.dev/brand) also applies to its logo; no endorsement is implied.

## Downloaded dependencies

See [the dependency inventory](docs/DEPENDENCIES.md). Those packages retain their own licenses and copyright notices. Their sources and licenses are downloaded by the build tools, rather than copied into this repository. When redistributing binaries, preserve all applicable dependency notices; the source MIT license does not replace them.
