import 'dart:io';

import 'package:cookdex/local_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'theme defaults to System and persists explicit choices locally',
    () async {
      final directory = await Directory.systemTemp.createTemp('cookdex-theme-');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/preferences.json';
      var preferences = await LocalPreferences.load(path);
      expect(preferences.themeMode, ThemeMode.system);
      for (final mode in ThemeMode.values) {
        preferences.setThemeMode(mode);
        await preferences.flush();
        preferences.dispose();
        preferences = await LocalPreferences.load(path);
        expect(preferences.themeMode, mode);
      }
      await preferences.flush();
      preferences.dispose();
    },
  );

  test('old or unknown theme preferences follow System', () async {
    final directory = await Directory.systemTemp.createTemp('cookdex-theme-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/preferences.json');
    for (final contents in ['{}', '{"themeMode":"unknown"}']) {
      await file.writeAsString(contents);
      final preferences = await LocalPreferences.load(file.path);
      expect(preferences.themeMode, ThemeMode.system);
      preferences.dispose();
      await preferences.flush();
    }
  });
}
