import 'dart:async';

import 'package:cookdex/export_service.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_store_test.dart' show recipe, summary;

class _Platform extends ExportPlatform {
  final List<(String, String, String?)> calls = [];
  ExportOutcome saveOutcome = ExportOutcome.saved;
  Object? shareError;
  Completer<ExportOutcome>? saveGate;

  @override
  Future<ExportOutcome> copy(String text) async {
    calls.add(('copy', text, null));
    return ExportOutcome.copied;
  }

  @override
  Future<ExportOutcome> save(String text, {required String filename}) async {
    calls.add(('save', text, filename));
    return saveGate?.future ?? saveOutcome;
  }

  @override
  Future<ExportOutcome> shareFile(
    String text, {
    required String filename,
  }) async {
    calls.add(('shareFile', text, filename));
    if (shareError != null) throw shareError!;
    return ExportOutcome.shareOpened;
  }

  @override
  Future<ExportOutcome> shareText(String text, {required String title}) async {
    calls.add(('shareText', text, title));
    if (shareError != null) throw shareError!;
    return ExportOutcome.shareOpened;
  }
}

void main() {
  test('selected recipes use cookbook text and count filenames', () async {
    final platform = _Platform();
    final service = ExportService(
      platform: platform,
      exporter: (value) async => 'Recipe ${value.id}',
    );
    final values = [recipe('first'), recipe('second')];
    await service.cookbook(values);
    for (final action in ExportAction.values) {
      await service.recipes(values, action);
    }
    expect(platform.calls.map((call) => call.$2).toSet(), {
      'Recipe first\n\nRecipe second',
    });
    expect(platform.calls[2].$3, '2 cookdex recipes.txt');
    await service.recipes([recipe('one', title: 'Cake')], ExportAction.save);
    expect(platform.calls.last.$3, 'Cake.txt');
    await expectLater(service.recipes([], ExportAction.copy), throwsStateError);
    await service.recipes(
      List.generate(51, (i) => recipe('$i')),
      ExportAction.copy,
    );
    expect(platform.calls.last.$2.split('Recipe ').length, 52);
  });

  test('recipe and cookbook text stay within re-import limits', () async {
    final platform = _Platform();
    final service = ExportService(
      platform: platform,
      exporter: (_) async => 'x' * (5 * 1024 * 1024 + 1),
    );
    await expectLater(
      service.recipe(recipe('a'), ExportAction.save),
      throwsStateError,
    );
    await expectLater(service.cookbook([recipe('a')]), throwsStateError);
    await expectLater(
      service.cookbook(List.generate(51, (i) => recipe('$i'))),
      throwsStateError,
    );
    expect(platform.calls, isEmpty);
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'recipe actions use the exact core text for message, file, copy and save',
    () async {
      final platform = _Platform();
      final exports = <Recipe>[];
      final service = ExportService(
        platform: platform,
        exporter: (value) async {
          exports.add(value);
          return 'Lemon cake\nIngredients:\n- 33/100 cup cream\nSteps:\n1. Mix';
        },
      );
      final value = recipe('cake', favorite: true, revision: 7);
      final outcomes = <ExportOutcome>[];
      for (final action in ExportAction.values) {
        outcomes.add(await service.recipe(value, action));
      }
      expect(exports, List.filled(4, value));
      expect(platform.calls.map((call) => call.$1), [
        'shareText',
        'shareFile',
        'copy',
        'save',
      ]);
      expect(platform.calls.map((call) => call.$2).toSet().length, 1);
      expect(platform.calls.first.$3, 'Lemon cake');
      expect(platform.calls[1].$3, 'Lemon cake.txt');
      expect(platform.calls[3].$3, 'Lemon cake.txt');
      expect(outcomes, [
        ExportOutcome.shareOpened,
        ExportOutcome.shareOpened,
        ExportOutcome.copied,
        ExportOutcome.saved,
      ]);
    },
  );

  test(
    'filenames preserve unicode and prevent paths or reserved device names',
    () async {
      final platform = _Platform();
      final service = ExportService(
        platform: platform,
        exporter: (_) async => 'recipe',
      );
      await service.recipe(
        recipe('a', title: '../Crème: brûlée/?. '),
        ExportAction.save,
      );
      expect(platform.calls.last.$3, '.._Crème_ brûlée__.txt');
      await service.recipe(recipe('b', title: 'CON'), ExportAction.shareFile);
      expect(platform.calls.last.$3, '_CON.txt');
      await service.recipe(recipe('c', title: '   '), ExportAction.save);
      expect(platform.calls.last.$3, 'recipe.txt');
      await service.recipe(recipe('d', title: '🍋' * 100), ExportAction.save);
      expect(platform.calls.last.$3!.runes.length, 84);
    },
  );

  test(
    'unavailable system sharing copies text; operational errors still fail',
    () async {
      final platform = _Platform()
        ..shareError = PlatformException(code: 'unavailable');
      final service = ExportService(
        platform: platform,
        exporter: (_) async => 'exact text',
      );
      expect(
        await service.recipe(recipe('a'), ExportAction.share),
        ExportOutcome.copiedFallback,
      );
      expect(platform.calls.map((call) => call.$1), ['shareText', 'copy']);
      expect(platform.calls.last.$2, 'exact text');
      platform.calls.clear();
      platform.shareError = MissingPluginException();
      expect(
        await service.recipe(recipe('a'), ExportAction.shareFile),
        ExportOutcome.copiedFallback,
      );
      expect(platform.calls.map((call) => call.$1), ['shareFile', 'copy']);
      platform.calls.clear();
      platform.shareError = PlatformException(
        code: 'share',
        message: 'Could not write file',
      );
      await expectLater(
        service.recipe(recipe('a'), ExportAction.shareFile),
        throwsA(isA<PlatformException>()),
      );
      expect(platform.calls.map((call) => call.$1), ['shareFile']);
    },
  );

  test(
    'cookbook preserves recipe order and never saves partial failed export',
    () async {
      final platform = _Platform();
      final service = ExportService(
        platform: platform,
        exporter: (value) async =>
            'Recipe ${value.id}\nIngredients:\n- 1 cup rice',
      );
      expect(
        await service.cookbook([recipe('first'), recipe('second')]),
        ExportOutcome.saved,
      );
      expect(platform.calls.single, (
        'save',
        'Recipe first\nIngredients:\n- 1 cup rice\n\nRecipe second\nIngredients:\n- 1 cup rice',
        'cookdex-cookbook.txt',
      ));
      platform.calls.clear();
      final failed = ExportService(
        platform: platform,
        exporter: (value) async {
          if (value.id == 'second') throw StateError('Invalid recipe');
          return 'first';
        },
      );
      await expectLater(
        failed.cookbook([recipe('first'), recipe('second')]),
        throwsStateError,
      );
      expect(platform.calls, isEmpty);
      await expectLater(service.cookbook([]), throwsStateError);
      expect(platform.calls, isEmpty);
    },
  );

  test('shopping text includes check state, exact quantities and unique source titles', () async {
    final platform = _Platform();
    final service = ExportService(platform: platform);
    const items = [
      ShoppingItem(
        categoryId: 'other',
        id: 'rice',
        name: 'Rice',
        measures: [],
        contributorScales: [],
        contributorIds: ['soup', 'soup', 'bowl'],
        checked: false,
        quantityText: '33/100 cup + 20 g',
      ),
      ShoppingItem(
        categoryId: 'other',
        id: 'salt',
        name: 'Salt',
        measures: [],
        contributorScales: [],
        contributorIds: [],
        checked: true,
        quantityText: 'to taste',
      ),
    ];
    await service.shopping(items, [
      summary(recipe('soup', title: 'Soup')),
      summary(recipe('bowl', title: 'Rice bowl')),
    ]);
    expect(platform.calls.single.$3, 'cookdex-shopping-list.txt');
    expect(
      platform.calls.single.$2,
      'Shopping list\n\n[ ] Rice — 33/100 cup + 20 g (From: Soup; Rice bowl)\n[x] Salt — to taste (Manual)\n',
    );
    platform.calls.clear();
    await service.shopping(items, []);
    expect(
      platform.calls.single.$2,
      contains('(From: Deleted recipe; Deleted recipe)'),
    );
    platform.calls.clear();
    await expectLater(service.shopping([], []), throwsStateError);
    expect(platform.calls, isEmpty);
  });

  test(
    'save waits for destination writing and preserves cancellation',
    () async {
      final platform = _Platform()..saveGate = Completer<ExportOutcome>();
      final service = ExportService(
        platform: platform,
        exporter: (_) async => 'text',
      );
      var finished = false;
      final operation = service.recipe(recipe('cake'), ExportAction.save).then((
        value,
      ) {
        finished = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);
      expect(platform.calls.single.$1, 'save');
      expect(finished, isFalse);
      platform.saveGate!.complete(ExportOutcome.cancelled);
      expect(await operation, ExportOutcome.cancelled);
    },
  );

  test(
    'native channel maps save cancel/success and rejects missing success',
    () async {
      const channel = MethodChannel('com.sylph.cookdex.dev/export');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      Object? reply = 'cancelled';
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return reply;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final platform = NativeExportPlatform();
      expect(
        await platform.save('hello', filename: 'recipe.txt'),
        ExportOutcome.cancelled,
      );
      expect(calls.single.method, 'saveText');
      expect(calls.single.arguments, {
        'text': 'hello',
        'filename': 'recipe.txt',
      });
      reply = 'saved';
      expect(
        await platform.save('hello', filename: 'recipe.txt'),
        ExportOutcome.saved,
      );
      reply = 'opened';
      expect(
        await platform.shareText('hello', title: 'Recipe'),
        ExportOutcome.shareOpened,
      );
      expect(calls.last.method, 'shareText');
      expect(
        await platform.shareFile('hello', filename: 'recipe.txt'),
        ExportOutcome.shareOpened,
      );
      expect(calls.last.method, 'shareFile');
      reply = null;
      await expectLater(
        platform.save('hello', filename: 'recipe.txt'),
        throwsStateError,
      );
    },
  );

  test('native copy sends exact text to the system clipboard', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodCall? received;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      received = call;
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    expect(
      await NativeExportPlatform().copy('33/100 cup'),
      ExportOutcome.copied,
    );
    expect(received!.method, 'Clipboard.setData');
    expect(received!.arguments, {'text': '33/100 cup'});
  });
}
