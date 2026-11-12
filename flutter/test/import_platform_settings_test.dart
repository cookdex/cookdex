import 'dart:convert';

import 'package:cookdex/import_platform.dart';
import 'package:cookdex/settings_platform.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _KeyPlatform implements ImportPlatform {
  _KeyPlatform(this.model, this.status);
  final String model;
  final int status;
  Map<String, dynamic>? sent;
  @override
  Future<SmartImportSettings> settings() async =>
      SmartImportSettings(hasKey: true, model: model);
  @override
  Future<ProviderReply> providerRequest(Uint8List body) async {
    sent = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
    return ProviderReply(status: status, bytes: Uint8List(0));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('custom-model key test errors suggest recommended without sending recipe data', () async {
    for (final status in [400, 403, 404, 429, 503]) {
      final platform = _KeyPlatform('synthetic-custom', status);
      await expectLater(
        SettingsPlatform().testKey(platform),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('recommended model'),
          ),
        ),
      );
      expect(platform.sent!['input'], 'Reply OK.');
      expect(platform.sent!['store'], false);
    }
  });
  const channel = MethodChannel('com.sylph.cookdex.dev/import');
  test('old device settings default to Standard and effort uses only native settings', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'settings') {
            return {'hasKey': true, 'model': 'gemini-3.5-flash-lite'};
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final platform = NativeImportPlatform();
    expect((await platform.settings()).effort, 'standard');
    await platform.saveSettings(
      key: '',
      model: 'custom-model',
      effort: 'thorough',
    );
    expect(calls.last.method, 'saveSettings');
    expect(calls.last.arguments, {
      'key': '',
      'model': 'custom-model',
      'effort': 'thorough',
    });
    await platform.removeKey();
    expect(calls.last.method, 'removeKey');
  });
}
