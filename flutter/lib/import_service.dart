import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'draft_storage.dart';
import 'import_diagnostics.dart';
import 'import_platform.dart';
import 'import_page_fetcher.dart';
import 'src/rust/api.dart';
export 'import_platform.dart';

class TextImportBlock {
  const TextImportBlock({required this.text, this.candidate});
  final String text;
  final Candidate? candidate;
}

bool isCookdexText(String value) => value
    .replaceFirst(RegExp(r'^[\s\uFEFF]*'), '')
    .startsWith('Recipe Book Text v1');

class ImportDiscovery {
  const ImportDiscovery({
    required this.candidates,
    this.warnings = const [],
    this.pageText = '',
    this.source = '',
    this.canTryWithAi = false,
    this.textBlocks = const [],
  });
  final List<Candidate> candidates;
  final List<String> warnings;
  final String pageText;
  final String source;
  final bool canTryWithAi;
  final List<TextImportBlock> textBlocks;
}

class ImportCancelled implements Exception {
  const ImportCancelled();
  @override
  String toString() => 'Import cancelled.';
}

abstract class ImportService {
  ImportPlatform get platform;
  Future<ImportDiscovery> text(String text);
  Future<ImportDiscovery> link(String url, {bool useAi = false});
  Future<ImportDiscovery> photos(List<ImportPhoto> photos);
  Future<Candidate> select(ImportDiscovery discovery, int index);
  Future<String> prompt();
  void cancel();
}

abstract interface class ImportServiceToolsProvider {
  Future<String> jsonPrompt({
    bool photos = false,
    ProviderMode mode = ProviderMode.recipe,
  });
  Future<String?> lastAiDiagnostics();
  Future<void> clearAiDiagnostics();
}

abstract interface class SmartTextImportService {
  Future<ImportDiscovery> smartText(String text);
}

extension ImportServiceTools on ImportService {
  Future<ImportDiscovery> smartText(String text) =>
      this is SmartTextImportService
      ? (this as SmartTextImportService).smartText(text)
      : Future.error(StateError('Smart Import is unavailable.'));

  Future<String> jsonPrompt({
    bool photos = false,
    ProviderMode mode = ProviderMode.recipe,
  }) => this is ImportServiceToolsProvider
      ? (this as ImportServiceToolsProvider).jsonPrompt(
          photos: photos,
          mode: mode,
        )
      : aiJsonPrompt(mode: mode, photos: photos, existingTags: const []);
  Future<String?> lastAiDiagnostics() => this is ImportServiceToolsProvider
      ? (this as ImportServiceToolsProvider).lastAiDiagnostics()
      : Future.value(null);
  Future<void> clearAiDiagnostics() => this is ImportServiceToolsProvider
      ? (this as ImportServiceToolsProvider).clearAiDiagnostics()
      : Future.value();
}

class NativeImportService
    implements
        ImportService,
        ImportServiceToolsProvider,
        SmartTextImportService {
  NativeImportService({
    ImportPlatform? platform,
    this.existingTags,
    DraftStorage? diagnosticsStorage,
  }) : platform = platform ?? NativeImportPlatform(),
       _diagnostics = ImportDiagnosticsStore(diagnosticsStorage);
  @override
  final ImportPlatform platform;
  final List<String> Function()? existingTags;
  final ImportDiagnosticsStore _diagnostics;
  final Map<String, AiReview> _reviews = {};
  final Map<String, List<String>> _warnings = {};
  int _epoch = 0;
  Operation? _operation;
  void _check(int epoch) {
    if (_epoch != epoch) throw const ImportCancelled();
  }

  @override
  void cancel() {
    _epoch++;
    _operation?.cancel();
    _operation = null;
    unawaited(platform.cancel().catchError((Object _) {}));
  }

  Future<void> _record(AiImportDiagnostic diagnostic, int epoch) async {
    if (_epoch != epoch) return;
    try {
      await _diagnostics.write(diagnostic.value);
    } catch (_) {
      // Diagnostics storage failure must not prevent recipe import.
    }
  }

  String _reason(Object error) => switch (error) {
    ServiceError(:final message) => message,
    StateError(:final message) => message.toString(),
    _ => error.toString(),
  };

  Future<ProviderOutput> _extract(
    ProviderInput input,
    SmartImportSettings settings,
    int epoch,
  ) async {
    _check(epoch);
    if (!settings.hasKey) {
      throw StateError('Add a Gemini key to use AI import.');
    }
    final diagnostic = AiImportDiagnostic(
      mode: input.mode == ProviderMode.urlRecipe
          ? 'Link (URL context)'
          : input.photos.isNotEmpty
          ? 'Photos'
          : 'Text',
      model: settings.model,
    );
    final operation = Operation();
    _operation = operation;
    try {
      final task = await ProviderTask.newInstance(
        input: input,
        model: settings.model,
        operation: operation,
      );
      while (true) {
        _check(epoch);
        final body = await task.request();
        _check(epoch);
        diagnostic.request(body);
        await _record(diagnostic, epoch);
        _check(epoch);
        final reply = await platform.providerRequest(Uint8List.fromList(body));
        _check(epoch);
        diagnostic.reply(reply.status, reply.bytes);
        await _record(diagnostic, epoch);
        _check(epoch);
        final output = await task.accept(
          status: reply.status,
          bytes: reply.bytes,
        );
        _check(epoch);
        if (output is ProviderOutput_Retry) {
          final problem = await task.validationProblem();
          _check(epoch);
          diagnostic.validation(
            '${problem ?? 'Response validation failed'}; retry requested.',
          );
          await _record(diagnostic, epoch);
          continue;
        }
        if (output is ProviderOutput_Recipe) {
          final review = await task.review();
          final warnings = await task.warnings();
          _check(epoch);
          _reviews[output.field0.id] = review;
          _warnings[output.field0.id] = warnings;
          diagnostic.value['warnings'] = warnings
              .map(redactImportDiagnostic)
              .toList();
        }
        diagnostic.validation('Accepted');
        await _record(diagnostic, epoch);
        _check(epoch);
        return output;
      }
    } catch (error) {
      diagnostic.validation(_reason(error));
      await _record(diagnostic, epoch);
      rethrow;
    } finally {
      if (identical(_operation, operation)) _operation = null;
    }
  }

  ProviderInput _input({
    String text = '',
    String source = '',
    List<ImportPhoto> photos = const [],
    ProviderMode mode = ProviderMode.recipe,
  }) => ProviderInput(
    text: text,
    source: source,
    targetTitle: '',
    photos: photos.map((photo) => photo.toPreparedPhoto()).toList(),
    mode: mode,
    existingTags: existingTags?.call() ?? const [],
  );
  Candidate _candidate(Recipe recipe, {List<String> warnings = const []}) =>
      Candidate(
        recipe: recipe,
        warnings: {...warnings, ...?_warnings.remove(recipe.id)}.toList(),
        ingredientSources: const [],
        aiReview: _reviews.remove(recipe.id),
      );
  Recipe _source(Recipe recipe, String source) {
    final f = recipe.fields;
    return Recipe(
      id: recipe.id,
      favorite: recipe.favorite,
      createdAt: recipe.createdAt,
      updatedAt: recipe.updatedAt,
      revision: recipe.revision,
      fields: RecipeFields(
        title: f.title,
        description: f.description,
        servings: f.servings,
        prepTime: f.prepTime,
        cookTime: f.cookTime,
        totalTime: f.totalTime,
        source: source,
        tags: f.tags,
        notes: f.notes,
        ingredients: f.ingredients,
        steps: f.steps,
      ),
    );
  }

  Future<ImportDiscovery> _basicText(
    String text,
    int epoch, {
    List<String> warnings = const [],
  }) async {
    final blocks = await splitRecipeText(text: text);
    _check(epoch);
    final candidates = <Candidate>[];
    final allWarnings = {...warnings};
    for (final block in blocks) {
      final parsed = await parseText(text: block);
      _check(epoch);
      candidates.addAll(parsed.candidates);
      allWarnings.addAll(parsed.warnings);
    }
    return ImportDiscovery(
      candidates: candidates,
      warnings: allWarnings.toList(),
    );
  }

  @override
  Future<ImportDiscovery> text(String text) async {
    final epoch = ++_epoch;
    if (utf8.encode(text).length > 5 * 1024 * 1024) {
      throw StateError('This file exceeds the 5 MB text import limit.');
    }
    // Each complete block is independently validated by the canonical Rust parser.
    // Malformed blocks are retained for explicit review, never sent to AI here.
    if (isCookdexText(text)) {
      final normalized = text
          .replaceAll('\r\n', '\n')
          .replaceFirst(RegExp(r'^[\s\uFEFF]*'), '');
      final starts = RegExp(
        r'^[ \t]*Recipe Book Text v1[^\n]*$',
        multiLine: true,
      ).allMatches(normalized).map((m) => m.start).toList();
      if (starts.length > 10000) {
        throw StateError('This file contains too many recipes.');
      }
      final blocks = <TextImportBlock>[];
      for (var i = 0; i < starts.length; i++) {
        final block = normalized.substring(
          starts[i],
          i + 1 < starts.length ? starts[i + 1] : normalized.length,
        );
        Candidate? candidate;
        try {
          final parsed = await parseText(text: block);
          if (parsed.candidates.length == 1) {
            candidate = parsed.candidates.single;
          }
        } on ServiceError {
          /* Unreadable block remains reviewable. */
        }
        _check(epoch);
        blocks.add(TextImportBlock(text: block, candidate: candidate));
      }
      if (blocks.isEmpty) blocks.add(TextImportBlock(text: text));
      return ImportDiscovery(
        candidates: blocks.map((b) => b.candidate).nonNulls.toList(),
        textBlocks: blocks,
      );
    }
    final settings = await platform.settings();
    _check(epoch);
    if (!settings.hasKey) return _basicText(text, epoch);
    try {
      final output = await _extract(
        _input(text: text),
        settings,
        epoch,
      ) as ProviderOutput_Recipe;
      return ImportDiscovery(candidates: [_candidate(output.field0)]);
    } on ImportCancelled {
      rethrow;
    } catch (error) {
      _check(epoch);
      final aiReason = redactImportDiagnostic(_reason(error));
      try {
        return await _basicText(
          text,
          epoch,
          warnings: [
            'AI import failed: $aiReason Used the basic parser. Review the recipe carefully.',
          ],
        );
      } on ImportCancelled {
        rethrow;
      } catch (fallbackError) {
        throw StateError(
          'AI import failed: $aiReason Basic parser failed: ${_reason(fallbackError)}',
        );
      }
    }
  }

  @override
  Future<ImportDiscovery> smartText(String text) async {
    if (utf8.encode(text).length > 5 * 1024 * 1024) {
      throw StateError('This file exceeds the 5 MB text import limit.');
    }
    final epoch = ++_epoch;
    final settings = await platform.settings();
    _check(epoch);
    final output = await _extract(
      _input(text: text),
      settings,
      epoch,
    ) as ProviderOutput_Recipe;
    return ImportDiscovery(candidates: [_candidate(output.field0)]);
  }

  @override
  Future<ImportDiscovery> link(String url, {bool useAi = false}) async {
    final epoch = ++_epoch;
    final checkedUrl = checkedImportUrl(url).toString();
    if (useAi) {
      final settings = await platform.settings();
      _check(epoch);
      if (!settings.hasKey) {
        throw StateError('Add a Gemini key to use AI import.');
      }
      final page = await platform.fetchPage(checkedUrl);
      _check(epoch);
      final source = checkedImportUrl(page.url).toString();
      final context = await pageAiContext(html: page.html);
      _check(epoch);
      // Only locally downloaded HTTPS content reaches AI. Remote URL context
      // cannot enforce our policy for every redirect hop.
      final output = await _extract(
        _input(text: context, source: source),
        settings,
        epoch,
      ) as ProviderOutput_Recipe;
      return ImportDiscovery(
        candidates: [_candidate(_source(output.field0, source))],
      );
    }
    final page = await platform.fetchPage(checkedUrl);
    _check(epoch);
    final source = checkedImportUrl(page.url).toString();
    final parsed = await inspectPage(html: page.html, url: source);
    _check(epoch);
    final incomplete = parsed.candidates.any(
      (candidate) =>
          candidate.recipe.fields.ingredients.isEmpty ||
          candidate.recipe.fields.steps.isEmpty,
    );
    return ImportDiscovery(
      candidates: parsed.candidates,
      warnings: [
        ...parsed.warnings,
        if (parsed.candidates.isEmpty) 'No embedded recipe data was found. Try with AI, or paste recipe text/use a photo.',
        if (incomplete) 'Embedded recipe data is missing ingredients or directions. Try with AI, or review and complete the recipe.',
      ],
      source: page.url,
      canTryWithAi: parsed.candidates.isEmpty || incomplete,
    );
  }

  @override
  Future<ImportDiscovery> photos(List<ImportPhoto> photos) async {
    final epoch = ++_epoch;
    if (photos.isEmpty || photos.length > 8) {
      throw StateError('Choose between 1 and 8 photos.');
    }
    if (photos.fold<int>(
          0,
          (sum, photo) => sum + ((photo.jpeg.length + 2) ~/ 3) * 4,
        ) >
        12 * 1024 * 1024) {
      throw StateError('Prepared photos exceed 12 MiB. Remove a photo.');
    }
    final settings = await platform.settings();
    final output = await _extract(
      _input(photos: photos),
      settings,
      epoch,
    ) as ProviderOutput_Recipe;
    return ImportDiscovery(candidates: [_candidate(output.field0)]);
  }

  @override
  Future<Candidate> select(ImportDiscovery discovery, int index) async =>
      discovery.candidates[index];

  @override
  Future<String> prompt() =>
      aiCopyPrompt(existingTags: existingTags?.call() ?? const []);
  @override
  Future<String> jsonPrompt({
    bool photos = false,
    ProviderMode mode = ProviderMode.recipe,
  }) => aiJsonPrompt(
    mode: mode,
    photos: photos,
    existingTags: existingTags?.call() ?? const [],
  );
  @override
  Future<String?> lastAiDiagnostics() => _diagnostics.read();
  @override
  Future<void> clearAiDiagnostics() => _diagnostics.clear();
}
