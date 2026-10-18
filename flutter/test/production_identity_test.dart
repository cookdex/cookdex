import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cookdex/app_identity.dart';
import 'package:cookdex/app_platform.dart';
import 'package:cookdex/settings_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.sylph.cookdex.dev/platform');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('Windows root uses selected identity without opening storage', () async {
    if (!Platform.isWindows) return;
    expect(
      await NativeAppPlatform().privateRoot(),
      '${Platform.environment['LOCALAPPDATA']}/$appId/flutter-v1',
    );
    expect(
      appId,
      isDevelopment ? 'com.sylph.cookdex.dev' : 'com.sylph.cookdex',
    );
  });
  test('mismatched native identity fails before opening storage', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async =>
          isDevelopment ? 'com.sylph.cookdex' : 'com.sylph.cookdex.dev',
    );
    await expectLater(NativeAppPlatform().verifyIdentity(), throwsStateError);
    messenger.setMockMethodCallHandler(channel, (_) async => appId);
    await NativeAppPlatform().verifyIdentity();
  });
  test(
    'Windows app info uses runtime metadata instead of a source version',
    () async {
      if (!Platform.isWindows) return;
      messenger.setMockMethodCallHandler(channel, (_) async => '2.3.4+23456');
      expect(
        await SettingsPlatform().appInfo(),
        contains('Version: 2.3.4+23456'),
      );
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      expect(
        await SettingsPlatform().appInfo(),
        contains('Version unavailable'),
      );
    },
  );
}
