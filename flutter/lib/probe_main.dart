// C1–C3 disposable native acceptance harness. No production data or screens.
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'core_probe.dart';
import 'c3_probe.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final result = await verifyCore();
  debugPrint('COOKDEX_C1_PROBE=$result');
  await verifyC3();
  debugPrint('COOKDEX_C3_PROBE=0');
  if (Platform.isWindows) exit(result);
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: Text('C1–C3 native probes: $result')),
    ),
  );
}
