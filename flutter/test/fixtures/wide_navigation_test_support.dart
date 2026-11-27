import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ingredient_section_screenshots_test.dart'
    show loadSectionCaptureFonts;

Future<void> loadWideNavigationFonts(
  WidgetTester tester, {
  bool desktop = false,
}) async {
  await loadSectionCaptureFonts(tester);
  if (!desktop) return;
  await tester.runAsync(() async {
    final font = FontLoader('Segoe UI');
    for (final name in ['segoeui.ttf', 'segoeuib.ttf']) {
      font.addFont(
        File('${Platform.environment['WINDIR']}/Fonts/$name')
            .readAsBytes()
            .then(ByteData.sublistView),
      );
    }
    await font.load();
  });
}
