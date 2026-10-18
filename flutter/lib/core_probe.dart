// C1 verification only. The application's typed FRB API is C3.
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

Future<int> verifyCore() => Isolate.run(() {
  final library = DynamicLibrary.open(
    Platform.isWindows
        ? const String.fromEnvironment('COOKDEX_TEST_PROBE_LIBRARY')
        : 'libcookdex_core_probe.so',
  );
  final probe = library
      .lookupFunction<
        Int32 Function(Pointer<Utf8>),
        int Function(Pointer<Utf8>)
      >('cookdex_c1_probe');
  final parent = Directory.systemTemp.path.toNativeUtf8();
  try {
    return probe(parent);
  } finally {
    malloc.free(parent);
  }
});
