import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cookdex/import_service.dart';
import 'package:cookdex/import_controller.dart';
import 'package:cookdex/draft_storage.dart';
import 'package:cookdex/import_diagnostics.dart';
import 'package:cookdex/import_page_fetcher.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_store_test.dart' show recipe;

class PlatformFake extends Fake implements ImportPlatform {
  bool hasKey = true;
  int settingsReads = 0, requests = 0;
  Object? fetchError;
  String? redirectedUrl;
  String rawReply = '{"steps":[]}';
  Completer<ProviderReply>? gate;
  @override
  Future<SmartImportSettings> settings() async {
    settingsReads++;
    return SmartImportSettings(hasKey: hasKey, model: 'test-model');
  }

  @override
  Future<void> cancel() async {}
  @override
  Future<ImportPage> fetchPage(String url) async {
    if (fetchError != null) throw fetchError!;
    return ImportPage(html: 'fixture', url: redirectedUrl ?? url);
  }

  @override
  Future<ProviderReply> providerRequest(Uint8List body) async {
    requests++;
    return gate == null
        ? ProviderReply(
            status: 200,
            bytes: Uint8List.fromList(utf8.encode(rawReply)),
          )
        : gate!.future;
  }
}

class OperationFake extends Fake implements Operation {
  @override
  bool cancel() => true;
}

class TaskFake extends Fake implements ProviderTask {
  TaskFake(this.outputs);
  final List<Object> outputs;
  @override
  Future<AiReview> review() async => AiReview(
    guessedFields: const ['servings'],
    guessedSteps: Uint32List.fromList([0]),
  );
  @override
  Future<List<String>> warnings() async => [
    'Ambiguous quantity kept for review.',
  ];
  @override
  Future<String?> validationProblem() async =>
      'Invalid quantity in first response';
  @override
  Future<Uint8List> request() async => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'system_instruction': outputs.length > 1
            ? 'Initial instructions'
            : 'Retry or final instructions',
        'input': [
          {'type': 'image', 'data': 'photo bytes are not diagnostics'},
        ],
      }),
    ),
  );
  @override
  Future<ProviderOutput> accept({
    required int status,
    required List<int> bytes,
  }) async {
    final value = outputs.removeAt(0);
    if (value is ProviderOutput) return value;
    throw value;
  }
}

class ApiFake extends Fake implements RustLibApi {
  bool ordinary = true;
  String? rejectText;
  List<String>? blocks;
  List<ProviderInput> sent = [];
  List<Object> outputs = [];
  List<Candidate> pageCandidates = [];
  int pageInspections = 0, parseCalls = 0, splitCalls = 0;
  final parsedTexts = <String>[];
  final List<List<String>> promptTags = [];
  final List<(ProviderMode, bool)> promptModes = [];
  @override
  Future<String> crateApiAiCopyPrompt({
    required List<String> existingTags,
  }) async {
    promptTags.add(existingTags.toList());
    return 'Shared Text v1 prompt: ${existingTags.join(',')}';
  }

  @override
  Future<String> crateApiAiJsonPrompt({
    required ProviderMode mode,
    required bool photos,
    required List<String> existingTags,
  }) async {
    promptTags.add(existingTags.toList());
    promptModes.add((mode, photos));
    return 'Shared JSON prompt: ${existingTags.join(',')}';
  }

  Candidate candidate(String title) => Candidate(
    recipe: recipe(title, title: title),
    warnings: const [],
    ingredientSources: ['0.33 cup cream'],
  );
  @override
  Operation crateApiOperationNew() => OperationFake();
  @override
  Future<List<String>> crateApiSplitRecipeText({required String text}) async =>
      _split(text);
  List<String> _split(String text) {
    splitCalls++;
    return blocks ?? [text];
  }

  @override
  Future<ImportCandidates> crateApiParseText({required String text}) async {
    parseCalls++;
    parsedTexts.add(text);
    if (text == rejectText) {
      throw const ServiceError(
        code: ErrorCode.validation,
        message: 'Basic parser could not normalize this block.',
      );
    }
    return ImportCandidates(
      candidates: [candidate(text)],
      warnings: const [],
      ordinary: ordinary,
    );
  }

  @override
  Future<ImportCandidates> crateApiInspectPage({
    required String html,
    required String url,
  }) async {
    pageInspections++;
    return ImportCandidates(
      candidates: pageCandidates,
      warnings: const [],
      ordinary: false,
    );
  }

  @override
  Future<String> crateApiPageAiContext({required String html}) async =>
      'Raw embedded JSON-LD and downloaded page text';
  @override
  Future<String> crateApiPageReadableText({required String html}) async =>
      'Full readable page';
  @override
  Future<ProviderTask> crateApiProviderTaskNew({
    required ProviderInput input,
    required String model,
    required Operation operation,
  }) async {
    sent.add(input);
    return TaskFake(outputs);
  }
}

void main() {
  late ApiFake api;
  late PlatformFake platform;
  late NativeImportService service;
  late MemoryDraftStorage diagnostics;
  setUp(() {
    api = ApiFake();
    RustLib.initMock(api: api);
    platform = PlatformFake();
    diagnostics = MemoryDraftStorage();
    service = NativeImportService(
      platform: platform,
      diagnosticsStorage: diagnostics,
    );
  });
  tearDown(RustLib.dispose);
  test(
    'explicit AI bypasses local parsing and returns guesses in one request',
    () async {
      service = NativeImportService(
        platform: platform,
        diagnosticsStorage: diagnostics,
        existingTags: () => ['Family favorite'],
      );
      api.outputs = [ProviderOutput.recipe(recipe('rolls'))];
      final found = await service.link(
        'https://www.momontimeout.com/the-best-dinner-rolls-recipe/',
        useAi: true,
      );
      expect(api.pageInspections, 0);
      expect(api.sent.single.mode, ProviderMode.recipe);
      expect(api.sent.single.text, contains('Raw embedded'));
      expect(api.sent.single.existingTags, ['Family favorite']);
      expect(found.candidates.single.aiReview!.guessedFields, ['servings']);
      expect(found.candidates.single.aiReview!.guessedSteps, [0]);
      await service.select(found, 0);
      expect(platform.requests, 1);
    },
  );
  test('explicit AI failure retains the actual provider reason', () async {
    api.outputs = [
      const ServiceError(
        code: ErrorCode.provider,
        message: 'URL retrieval failed: robots.txt blocked access',
      ),
    ];
    await expectLater(
      service.link('https://example.com/recipe', useAi: true),
      throwsA(
        isA<ServiceError>().having(
          (e) => e.message,
          'reason',
          contains('robots.txt'),
        ),
      ),
    );
    expect(api.pageInspections, 0);
  });
  test('blocked download never falls through to remote AI retrieval', () async {
    platform.fetchError = const HttpException('Download blocked (HTTP 403).');
    for (final useAi in [false, true]) {
      await expectLater(
        service.link('https://example.com/recipe', useAi: useAi),
        throwsA(isA<HttpException>()),
      );
    }
    expect(platform.requests, 0);
    expect(api.sent, isEmpty);
  });
  test(
    'HTTP inputs and insecure redirects never reach parsing or AI',
    () async {
      for (final useAi in [false, true]) {
        await expectLater(
          service.link('http://example.com/recipe', useAi: useAi),
          throwsA(isA<InsecureImportUrl>()),
        );
        platform.fetchError = const InsecureImportUrl();
        await expectLater(
          service.link('https://example.com/recipe', useAi: useAi),
          throwsA(isA<InsecureImportUrl>()),
        );
        platform.fetchError = null;
        platform.redirectedUrl = 'http://example.com/final';
        await expectLater(
          service.link('https://example.com/recipe', useAi: useAi),
          throwsA(isA<InsecureImportUrl>()),
        );
      }
      expect(platform.requests, 0);
      expect(api.pageInspections, 0);
      expect(api.sent, isEmpty);
    },
  );
  test(
    'invalid/private link and missing key never invoke URL fallback',
    () async {
      platform.fetchError = const HttpException('Download failed');
      await expectLater(
        service.link('http://127.0.0.1/recipe', useAi: true),
        throwsFormatException,
      );
      platform.hasKey = false;
      await expectLater(
        service.link('https://example.com/recipe', useAi: true),
        throwsA(isA<StateError>()),
      );
      expect(platform.requests, 0);
    },
  );
  test(
    'insecure link displays paste guidance without offering AI retry',
    () async {
      final controller = ImportController(
        service: service,
        storage: MemoryDraftStorage(),
      )..tab = ImportTab.link;
      controller.link = 'http://example.com/recipe';
      expect(await controller.discover(), isNull);
      expect(controller.error, insecureImportMessage);
      expect(controller.canTryWithAi, false);
      await controller.flush();
      controller.dispose();
    },
  );
  test('own format never consults credentials or a provider', () async {
    api.ordinary = false;
    final result = await service.text('Recipe Book Text v1');
    expect(result.candidates.length, 1);
    expect(platform.settingsReads, 0);
    expect(platform.requests, 0);
  });
  test('ordinary text uses basic parser without a key', () async {
    platform.hasKey = false;
    final result = await service.text('Soup');
    expect(result.candidates.single.recipe.fields.title, 'Soup');
    expect(platform.requests, 0);
  });
  test('configured ordinary AI bypasses basic validation', () async {
    api.rejectText = 'unwrapped source paragraph';
    api.outputs = [ProviderOutput.recipe(recipe('result'))];
    await service.text(api.rejectText!);
    expect(api.sent.single.text, api.rejectText);
  });
  test('invalid cookdex format does not fall through to AI', () async {
    api.rejectText = 'Recipe Book Text v1 broken';
    final result = await service.text(api.rejectText!);
    expect(result.candidates, isEmpty);
    expect(result.textBlocks.single.text, api.rejectText);
    expect(result.textBlocks.single.candidate, isNull);
    expect(platform.settingsReads, 0);
    expect(api.sent, isEmpty);
  });
  test(
    'malformed leading header remains visible before a valid block',
    () async {
      const broken = 'Recipe Book Text v1 broken\nUnfinished recipe\n';
      const valid = 'Recipe Book Text v1\nValid recipe';
      api.rejectText = broken;
      final result = await service.text('$broken$valid');
      expect(result.textBlocks, hasLength(2));
      expect(result.textBlocks.first.text, broken);
      expect(result.textBlocks.first.candidate, isNull);
      expect(result.textBlocks.last.candidate, isNotNull);
      expect(result.candidates, hasLength(1));
      expect(platform.settingsReads, 0);
      expect(platform.requests, 0);
    },
  );
  test(
    'Text v1 blocks parse independently and retain malformed raw text',
    () async {
      const first = 'Recipe Book Text v1\nFirst\n';
      const broken = 'Recipe Book Text v1\nBroken\n';
      const last = 'Recipe Book Text v1\nLast';
      api.rejectText = broken;
      final result = await service.text(
        '\uFEFF\r\n${'$first$broken$last'.replaceAll('\n', '\r\n')}',
      );
      expect(api.parsedTexts, [first, broken, last]);
      expect(result.textBlocks.map((b) => b.text), [first, broken, last]);
      expect(result.textBlocks[0].candidate, isNotNull);
      expect(result.textBlocks[1].candidate, isNull);
      expect(result.textBlocks[2].candidate, isNotNull);
      expect(result.candidates, hasLength(2));
      expect(platform.settingsReads, 0);
      expect(platform.requests, 0);
    },
  );
  test(
    'malformed Text v1 only reaches provider after explicit smartText',
    () async {
      const input = 'Recipe Book Text v1\nBroken';
      api.rejectText = input;
      final result = await service.text(input);
      expect(result.textBlocks.single.candidate, isNull);
      expect(platform.settingsReads, 0);
      api.outputs = [ProviderOutput.recipe(recipe('recovered'))];
      final recovered = await service.smartText(result.textBlocks.single.text);
      expect(recovered.candidates, hasLength(1));
      expect(api.sent.single.text, input);
      expect(platform.requests, 1);
    },
  );
  test(
    'text import size limit counts UTF-8 bytes before parser or provider',
    () async {
      final oversized = 'é' * (5 * 1024 * 1024 ~/ 2 + 1);
      await expectLater(service.text(oversized), throwsStateError);
      await expectLater(service.smartText(oversized), throwsStateError);
      expect(api.parseCalls, 0);
      expect(platform.settingsReads, 0);
      expect(platform.requests, 0);
    },
  );
  test('configured ordinary multi recipe input goes whole to AI for the main recipe', () async {
    api.rejectText = 'first unwrapped block';
    api.blocks = [api.rejectText!, 'second block'];
    api.outputs = [ProviderOutput.recipe(recipe('main', title: 'main'))];
    final discovered = await service.text('both recipes verbatim');
    expect(discovered.candidates.single.recipe.fields.title, 'main');
    expect(api.sent.single.text, 'both recipes verbatim');
    expect(api.parseCalls, 0);
    expect(api.splitCalls, 0);
    await service.select(discovered, 0);
    expect(platform.requests, 1);
  });
  test('without a key ordinary multi recipes use a local chooser', () async {
    platform.hasKey = false;
    api.blocks = ['First 0.33', 'Second 33/100'];
    final result = await service.text('both recipes');
    expect(result.candidates.length, 2);
    expect(
      (await service.select(result, 1)).recipe.fields.title,
      'Second 33/100',
    );
    expect(api.sent, isEmpty);
    expect(platform.settingsReads, 1);
  });
  test('malformed response retry comes from Rust and selected text remains identical', () async {
    api.outputs = [
      const ProviderOutput.retry(),
      ProviderOutput.recipe(recipe('result')),
    ];
    await service.text('Only selected source');
    expect(platform.requests, 2);
    expect(api.sent.single.text, 'Only selected source');
  });
  test('provider quota failure falls back locally without retry and retains reason', () async {
    api.outputs = [
      const ServiceError(code: ErrorCode.quota, message: 'Quota exhausted'),
    ];
    final result = await service.text('Selected');
    expect(result.candidates.single.recipe.fields.title, 'Selected');
    expect(result.warnings.single, contains('Quota exhausted'));
    expect(result.warnings.single, contains('basic parser'));
    expect(platform.requests, 1);
    expect(api.parseCalls, 1);
  });
  test('cancel ignores a late provider response', () async {
    api.outputs = [ProviderOutput.recipe(recipe('late'))];
    platform.gate = Completer<ProviderReply>();
    final pending = service.text('Selected');
    while (platform.requests == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    service.cancel();
    platform.gate!.complete(
      ProviderReply(
        status: 200,
        bytes: Uint8List.fromList(utf8.encode(platform.rawReply)),
      ),
    );
    await expectLater(pending, throwsA(isA<ImportCancelled>()));
  });
  test('unchecked local page selection never reads settings or enhances ingredients', () async {
    api.pageCandidates = [api.candidate('First'), api.candidate('Second')];
    final result = await service.link('https://example.com/recipe');
    final selected = await service.select(result, 1);
    expect(selected.recipe.fields.title, 'Second');
    expect(platform.requests, 0);
    expect(platform.settingsReads, 0);
    expect(api.sent, isEmpty);
  });
  test(
    'unchecked missing embedded data offers explicit AI without provider work',
    () async {
      final result = await service.link('https://example.com/recipe');
      expect(result.candidates, isEmpty);
      expect(result.canTryWithAi, true);
      expect(result.warnings, contains(contains('No embedded recipe')));
      expect(platform.settingsReads, 0);
      expect(platform.requests, 0);
    },
  );
  test(
    'unchecked incomplete embedded candidate stays local on selection',
    () async {
      final source = Recipe(
        id: 'incomplete',
        favorite: false,
        createdAt: '',
        updatedAt: '',
        revision: 1,
        fields: const RecipeFields(
          title: 'Incomplete',
          description: '',
          servings: '',
          prepTime: '',
          cookTime: '',
          totalTime: '',
          source: '',
          tags: [],
          notes: '',
          ingredients: [],
          steps: [],
        ),
      );
      api.pageCandidates = [
        Candidate(
          recipe: source,
          warnings: const [],
          ingredientSources: ['cream'],
        ),
      ];
      final result = await service.link('https://example.com/recipe');
      expect(result.canTryWithAi, true);
      await service.select(result, 0);
      expect(platform.settingsReads, 0);
      expect(platform.requests, 0);
    },
  );
  test('explicit AI uses the final redirected URL for downloaded context and saved source', () async {
    platform.redirectedUrl = 'https://example.com/final';
    api.outputs = [ProviderOutput.recipe(recipe('redirected'))];
    final result = await service.link('https://example.com/start', useAi: true);
    expect(api.sent.single.source, platform.redirectedUrl);
    expect(
      result.candidates.single.recipe.fields.source,
      platform.redirectedUrl,
    );
    expect(api.pageInspections, 0);
  });
  test('provider warnings are retained on the imported candidate', () async {
    api.outputs = [ProviderOutput.recipe(recipe('warned'))];
    final result = await service.text('Recipe source');
    expect(result.candidates.single.warnings, [
      'Ambiguous quantity kept for review.',
    ]);
  });
  test(
    'a basic fallback failure still reports the original AI failure reason',
    () async {
      api.rejectText = 'unreadable';
      api.outputs = [
        const ServiceError(code: ErrorCode.quota, message: 'Quota exhausted'),
      ];
      await expectLater(
        service.text('unreadable'),
        throwsA(
          isA<StateError>()
              .having(
                (e) => e.message,
                'AI reason',
                contains('Quota exhausted'),
              )
              .having(
                (e) => e.message,
                'local reason',
                contains('Basic parser could not normalize'),
              ),
        ),
      );
    },
  );
  test(
    'photo limit counts base64 expansion before requesting credentials',
    () async {
      final photo = ImportPhoto(
        id: 'large',
        jpeg: Uint8List(9 * 1024 * 1024 + 1),
      );
      await expectLater(service.photos([photo]), throwsStateError);
      expect(platform.settingsReads, 0);
    },
  );
  test(
    'both prompt tools use shared core and read current tags each time',
    () async {
      var tags = ['First'];
      service = NativeImportService(
        platform: platform,
        diagnosticsStorage: diagnostics,
        existingTags: () => tags,
      );
      expect(await service.prompt(), 'Shared Text v1 prompt: First');
      tags = ['Fresh'];
      expect(
        await service.jsonPrompt(mode: ProviderMode.urlRecipe, photos: false),
        'Shared JSON prompt: Fresh',
      );
      expect(api.promptTags, [
        ['First'],
        ['Fresh'],
      ]);
      expect(api.promptModes.single, (ProviderMode.urlRecipe, false));
    },
  );
  test('diagnostics retain each attempt instructions reply and validation, redact keys, and clear', () async {
    platform.rawReply =
        '{"message":"AIzaSyntheticSecret12345 malformed reply"}';
    api.outputs = [
      const ProviderOutput.retry(),
      ProviderOutput.recipe(recipe('accepted')),
    ];
    await service.text('Source text');
    final saved = await service.lastAiDiagnostics();
    expect(saved, contains('test-model'));
    expect(saved, contains('Text'));
    expect(saved, contains('Initial instructions'));
    expect(saved, contains('Retry or final instructions'));
    expect(saved, contains('retry requested'));
    expect(saved, contains('Invalid quantity in first response'));
    expect(saved, contains('Accepted'));
    expect(saved, contains('[redacted key]'));
    expect(saved, isNot(contains('AIza')));
    expect(saved, isNot(contains('photo bytes')));
    expect((jsonDecode(saved!)['attempts'] as List).length, 2);
    await service.clearAiDiagnostics();
    expect(await service.lastAiDiagnostics(), isNull);
  });
  test(
    'diagnostics retain terminal validation failure before text falls back',
    () async {
      api.outputs = [
        const ServiceError(
          code: ErrorCode.provider,
          message: 'Invalid quantity: range',
        ),
      ];
      await service.text('Source text');
      expect(
        await service.lastAiDiagnostics(),
        contains('Invalid quantity: range'),
      );
    },
  );
  test(
    'last diagnostics persist in an isolated file across services',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'cookdex-import-diagnostics-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final path = '${temporary.path}/last-ai-import.json';
      service = NativeImportService(
        platform: platform,
        diagnosticsStorage: FileDraftStorage(path),
      );
      api.outputs = [ProviderOutput.recipe(recipe('saved'))];
      await service.text('Source text');
      final reopened = NativeImportService(
        platform: platform,
        diagnosticsStorage: FileDraftStorage(path),
      );
      expect(await reopened.lastAiDiagnostics(), contains('Accepted'));
      await reopened.clearAiDiagnostics();
      expect(await File(path).exists(), false);
    },
  );
  test('diagnostic redaction bounds oversized responses', () {
    final bounded = redactImportDiagnostic('x' * (600 * 1024));
    expect(bounded, endsWith('[truncated]'));
    expect(bounded.length, lessThan(513 * 1024));
  });
  test(
    'diagnostics retain the full provider reply through its 2 MiB limit',
    () async {
      platform.rawReply = 'x' * (2 * 1024 * 1024);
      api.outputs = [
        const ServiceError(
          code: ErrorCode.provider,
          message: 'Malformed reply',
        ),
      ];
      await service.text('Source text');
      final saved = jsonDecode((await service.lastAiDiagnostics())!) as Map;
      expect((saved['attempts'] as List).single['reply'], platform.rawReply);
    },
  );
  test(
    'page URL policy blocks private, reserved, mapped and credential URLs',
    () {
      for (final ip in [
        '127.0.0.1',
        '10.1.1.1',
        '169.254.169.254',
        '100.64.1.2',
        '192.168.1.1',
        '198.51.100.1',
        '::1',
        '::ffff:127.0.0.1',
        'fc00::1',
        '2001:db8::1',
      ]) {
        expect(isPublicImportAddress(InternetAddress(ip)), false, reason: ip);
      }
      expect(isPublicImportAddress(InternetAddress('8.8.8.8')), true);
      for (final url in [
        'http://127.0.0.1',
        'https://recipebook@local.invalid',
        'file:///x',
        'http://router.local',
        'http://localhost',
        'http://host.lan',
      ]) {
        expect(() => checkedImportUrl(url), throwsFormatException, reason: url);
      }
      expect(checkedImportUrl('https://example.com/a').host, 'example.com');
    },
  );
}
