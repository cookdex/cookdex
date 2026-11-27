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
    final settings = await platform.settings();
    expect(settings.effort, 'standard');
    expect(settings.thinking, 'low');
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

  for (final (stored, thinking) in [
    ('standard', 'low'),
    ('thorough', 'high'),
    ('default', 'default'),
    ('minimal', 'minimal'),
    ('low', 'low'),
    ('medium', 'medium'),
    ('high', 'high'),
  ]) {
    test(
      'native settings preserve $stored and expose $thinking thinking',
      () async {
        final calls = <MethodCall>[];
        var saved = <String, Object>{
          'hasKey': true,
          'model': 'synthetic-existing-model',
          'effort': stored,
        };
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'settings') return saved;
          if (call.method == 'saveSettings') {
            final values = Map<String, Object>.from(call.arguments as Map);
            saved = {
              'hasKey': saved['hasKey']!,
              'model': values['model']!,
              'effort': values['effort']!,
            };
          }
          return null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        final platform = NativeImportPlatform();
        final original = await platform.settings();
        expect(original.model, 'synthetic-existing-model');
        expect(original.effort, stored);
        expect(original.thinking, thinking);
        expect(saved['effort'], stored);
        expect(calls.map((call) => call.method), ['settings']);

        await platform.saveSettings(
          key: '',
          model: 'synthetic-custom-model',
          effort: stored,
        );
        expect(calls.last.arguments, {
          'key': '',
          'model': 'synthetic-custom-model',
          'effort': stored,
        });
        final restored = await platform.settings();
        expect(restored.hasKey, isTrue);
        expect(restored.model, 'synthetic-custom-model');
        expect(restored.effort, stored);
        expect(restored.thinking, thinking);
        expect(calls.map((call) => call.method), [
          'settings',
          'saveSettings',
          'settings',
        ]);
      },
    );
  }
}
