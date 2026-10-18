import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import 'src/rust/frb_generated.dart';

Future<void> initializeBridge() => RustLib.init(
  externalLibrary: ExternalLibrary.open(
    Platform.isWindows
        ? '${File(Platform.resolvedExecutable).parent.path}/cookdex_bridge.dll'
        : 'libcookdex_bridge.so',
  ),
);
