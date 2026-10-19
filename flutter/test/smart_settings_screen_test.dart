import 'dart:async';

import 'package:cookdex/import_service.dart';
import 'package:cookdex/src/rust/api.dart' show ProviderMode;
import 'package:cookdex/ui/smart_settings_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Platform implements ImportPlatform {
  bool hasKey = true;
  String model = 'chosen-model';
  String? receivedKey;
  String? receivedModel;
  bool failSave = false;
  bool failLoad = false;
  bool failRemove = false;
  int saves = 0;
  int removes = 0;
  Completer<void>? saveGate;

  @override
  Future<SmartImportSettings> settings() async {
    if (failLoad) throw StateError('synthetic read failure');
    return SmartImportSettings(hasKey: hasKey, model: model);
  }

  @override
  Future<void> saveSettings({
    required String key,
    required String model,
  }) async {
    saves++;
    receivedKey = key;
    receivedModel = model;
    if (saveGate != null) await saveGate!.future;
    if (failSave) throw StateError('synthetic save failure');
    if (key.isNotEmpty) hasKey = true;
    this.model = model;
  }

  @override
  Future<void> removeKey() async {
    removes++;
    if (failRemove) throw StateError('synthetic removal failure');
    hasKey = false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Service implements ImportService, ImportServiceToolsProvider {
  @override
  final _Platform platform = _Platform();
  final modes = <(ProviderMode, bool)>[];
  String? diagnostic = 'Validation: accepted\nAIzaSyntheticSecret';
  bool failClear = false;
  bool failPrompt = false;
  int clears = 0;

  @override
  Future<String> jsonPrompt({
    bool photos = false,
    ProviderMode mode = ProviderMode.recipe,
  }) async {
    if (failPrompt) throw StateError('synthetic prompt failure');
    modes.add((mode, photos));
    return 'JSON ${mode.name} photos=$photos';
  }

  @override
  Future<String> prompt() async => 'Copy Text v1 recipe instructions';
  @override
  Future<String?> lastAiDiagnostics() async => diagnostic;
  @override
  Future<void> clearAiDiagnostics() async {
    clears++;
    if (failClear) throw StateError('synthetic clear failure');
    diagnostic = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester,
  _Service service, {
  Future<void> Function()? testKey,
  Future<void> Function(String)? openUrl,
  double textScale = 1,
  double width = 400,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: cookdexTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: SmartSettingsScreen(
        service: service,
        testKey: testKey ?? () async {},
        openUrl: openUrl ?? (_) async {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

bool _testEnabled(WidgetTester tester) =>
    tester
        .widget<OutlinedButton>(
          find.ancestor(
            of: find.text('Test key'),
            matching: find.byType(OutlinedButton),
          ),
        )
        .onPressed !=
    null;

void main() {
  testWidgets('saved key stays hidden and testing requires an explicit tap', (
    tester,
  ) async {
    final service = _Service();
    var tests = 0;
    await _pump(tester, service, testKey: () async => tests++);
    expect(tests, 0);
    expect(find.text('Key saved. Leave blank to keep it.'), findsOneWidget);
    final key = tester.widget<TextField>(_field('Gemini key'));
    expect(key.autocorrect, isFalse);
    expect(key.enableSuggestions, isFalse);
    expect(key.enableIMEPersonalizedLearning, isFalse);
    expect(key.textCapitalization, TextCapitalization.none);
    expect(key.controller!.text, isEmpty);
    expect(key.obscureText, isTrue);
    expect(key.autocorrect, isFalse);
    expect(key.enableSuggestions, isFalse);
    expect(_testEnabled(tester), isTrue);
    await _tap(tester, 'Test key');
    expect(tests, 1);
    expect(find.text('Gemini key works'), findsOneWidget);
    await tester.enterText(_field('Gemini key'), 'new-secret');
    await tester.pump();
    expect(_testEnabled(tester), isFalse);
    await tester.enterText(_field('Gemini key'), '');
    await tester.enterText(_field('Model'), 'unsaved-model');
    await tester.pump();
    expect(_testEnabled(tester), isFalse);
    expect(tests, 1);
  });

  testWidgets('no saved key disables testing and removal without live calls', (
    tester,
  ) async {
    final service = _Service()..platform.hasKey = false;
    var tests = 0;
    await _pump(tester, service, testKey: () async => tests++);
    expect(find.text('No key saved'), findsOneWidget);
    expect(_testEnabled(tester), isFalse);
    final remove = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('Remove key'),
        matching: find.byType(TextButton),
      ),
    );
    expect(remove.onPressed, isNull);
    await tester.enterText(_field('Gemini key'), 'new-secret');
    await tester.pump();
    expect(_testEnabled(tester), isFalse);
    expect(tests, 0);
  });

  testWidgets('save keeps a blank key and clears a successfully replaced key', (
    tester,
  ) async {
    final service = _Service();
    var tests = 0;
    await _pump(tester, service, testKey: () async => tests++);
    await tester.enterText(_field('Model'), ' another-model ');
    await _tap(tester, 'Save');
    expect(service.platform.receivedKey, '');
    expect(service.platform.receivedModel, 'another-model');
    expect(_testEnabled(tester), isTrue);
    await tester.enterText(_field('Gemini key'), 'synthetic-new-key');
    await _tap(tester, 'Save');
    expect(service.platform.receivedKey, 'synthetic-new-key');
    expect(tester.widget<TextField>(_field('Gemini key')).controller!.text, '');
    expect(tests, 0);
    service.platform.failSave = true;
    await tester.enterText(_field('Gemini key'), 'retry-secret');
    await _tap(tester, 'Save');
    expect(find.text('Could not save Smart Import settings.'), findsOneWidget);
    expect(
      tester.widget<TextField>(_field('Gemini key')).controller!.text,
      'retry-secret',
    );
  });

  testWidgets('remove is red, confirms, and preserves state after failure', (
    tester,
  ) async {
    final service = _Service();
    await _pump(tester, service);
    final remove = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('Remove key'),
        matching: find.byType(TextButton),
      ),
    );
    expect(remove.style!.foregroundColor!.resolve({}), cookdexColors.error);
    await _tap(tester, 'Remove key');
    expect(service.platform.removes, 0);
    await _tap(tester, 'Cancel');
    expect(service.platform.hasKey, isTrue);
    service.platform.failRemove = true;
    await _tap(tester, 'Remove key');
    await _tap(tester, 'Remove key');
    expect(find.text('Could not remove the key.'), findsOneWidget);
    expect(service.platform.hasKey, isTrue);
    service.platform.failRemove = false;
    await _tap(tester, 'Remove key');
    await _tap(tester, 'Remove key');
    expect(service.platform.hasKey, isFalse);
    expect(find.text('No key saved'), findsOneWidget);
    expect(_testEnabled(tester), isFalse);
  });

  testWidgets('Google note and key/pricing links use supplied URL callback', (
    tester,
  ) async {
    final opened = <String>[];
    await _pump(tester, _Service(), openUrl: (url) async => opened.add(url));
    expect(
      find.text(
        'AI imports send selected inputs to Google. Keys stay on this device.',
      ),
      findsOneWidget,
    );
    expect(opened, isEmpty);
    await _tap(tester, 'Get a Gemini key');
    await _tap(tester, 'Pricing and data use');
    expect(opened, [
      'https://aistudio.google.com/apikey',
      'https://ai.google.dev/gemini-api/docs/pricing',
    ]);
  });

  testWidgets('prompts are local and include JSON variants plus Copy Text v1', (
    tester,
  ) async {
    final service = _Service();
    var tests = 0;
    await _pump(tester, service, testKey: () async => tests++);
    await _tap(tester, 'View prompts');
    expect(service.modes, [
      (ProviderMode.recipe, false),
      (ProviderMode.urlRecipe, false),
      (ProviderMode.recipe, true),
    ]);
    expect(find.text('In-app JSON prompt (Text)'), findsOneWidget);
    expect(find.text('In-app JSON prompt (Link)'), findsOneWidget);
    expect(find.text('In-app JSON prompt (Photos)'), findsOneWidget);
    expect(find.text('Copy Text v1 prompt'), findsOneWidget);
    expect(find.text('Copy Text v1 recipe instructions'), findsOneWidget);
    await _tap(tester, 'Close');
    expect(tests, 0);
    service.failPrompt = true;
    await _tap(tester, 'View prompts');
    expect(find.text('Could not load the AI prompts.'), findsOneWidget);
  });

  testWidgets('diagnostic is redacted and local; clear failure allows retry', (
    tester,
  ) async {
    final service = _Service();
    await _pump(tester, service);
    await _tap(tester, 'Last Smart Import');
    expect(find.text('Validation: accepted\n[redacted key]'), findsOneWidget);
    expect(find.textContaining('AIzaSyntheticSecret'), findsNothing);
    service.failClear = true;
    await _tap(tester, 'Clear record');
    expect(find.text('Could not clear the last Smart Import.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    service.failClear = false;
    await _tap(tester, 'Clear record');
    expect(service.diagnostic, isNull);
    await _tap(tester, 'Last Smart Import');
    expect(find.text('No Smart Import has been recorded.'), findsOneWidget);
    expect(find.text('Clear record'), findsNothing);
  });

  testWidgets(
    'failed load offers retry and key-test errors redact credentials',
    (tester) async {
      final service = _Service()..platform.failLoad = true;
      await _pump(
        tester,
        service,
        testKey: () async => throw StateError('Invalid AIzaSyntheticSecret'),
      );
      expect(
        find.text('Could not load Smart Import settings.'),
        findsOneWidget,
      );
      final loadError = tester.getRect(
        find.text('Could not load Smart Import settings.'),
      );
      final retry = tester.getRect(find.text('Retry'));
      expect(retry.top, greaterThan(loadError.bottom));
      expect(retry.top - loadError.bottom, lessThan(48));
      expect(
        retry.bottom,
        lessThan(tester.getTopLeft(_field('Gemini key')).dy),
      );
      expect(_testEnabled(tester), isFalse);
      service.platform.failLoad = false;
      await _tap(tester, 'Retry');
      await _tap(tester, 'Test key');
      expect(find.text('Invalid [redacted key]'), findsOneWidget);
    },
  );

  testWidgets('save is serialized and busy disables input and live testing', (
    tester,
  ) async {
    final service = _Service()..platform.saveGate = Completer<void>();
    await _pump(tester, service);
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(service.platform.saves, 1);
    expect(tester.widget<TextField>(_field('Gemini key')).enabled, isFalse);
    expect(_testEnabled(tester), isFalse);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    service.platform.saveGate!.complete();
    await tester.pumpAndSettle();
    expect(_testEnabled(tester), isTrue);
  });

  testWidgets('320dp at double text keeps fields, actions and dialogs usable', (
    tester,
  ) async {
    await _pump(tester, _Service(), width: 320, textScale: 2);
    for (final label in [
      'Save',
      'Test key',
      'Remove key',
      'Get a Gemini key',
      'Pricing and data use',
      'View prompts',
      'Last Smart Import',
    ]) {
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: label);
    }
    await _tap(tester, 'Last Smart Import');
    expect(tester.takeException(), isNull);
    await _tap(tester, 'Close');
    await _tap(tester, 'View prompts');
    expect(tester.takeException(), isNull);
    await _tap(tester, 'Close');
    expect(tester.takeException(), isNull);
  });
}
