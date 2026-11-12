import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'draft_storage.dart';
import 'import_diagnostics.dart';
import 'import_platform.dart';
import 'local_preferences.dart';
import 'import_page_fetcher.dart';
import 'social_import_page.dart';
import 'youtube_import.dart';
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
    this.websiteAiHint = false,
    this.textBlocks = const [],
    this.sourceLine = '',
    this.fallback = false,
    this.canRetryWatch = false,
    this.canWatchAnyway = false,
    this.needsYoutubeKey = false,
    this.blockedSite,
  });
  final List<Candidate> candidates;
  final List<String> warnings;
  final String pageText;
  final String source;
  final bool websiteAiHint;
  final List<TextImportBlock> textBlocks;
  final String sourceLine;
  final bool fallback;
  final bool canRetryWatch;
  final bool canWatchAnyway;
  final bool needsYoutubeKey;
  final SocialSite? blockedSite;
}

class ImportCancelled implements Exception {
  const ImportCancelled();
  @override
  String toString() => 'Import cancelled.';
}

enum ImportPhase {
  readingText('Reading the text…'),
  readingPage('Reading the page…'),
  readingDescription('Reading the description…'),
  openingRecipePage('Opening the recipe page…'),
  watchingVideo('Watching the video…'),
  readingPhotos('Reading your photos…'),
  writing('Writing the recipe…'),
  checking('Double-checking…'),
  retrying('Trying again…');

  const ImportPhase(this.label);
  final String label;
}

typedef ImportPhaseCallback = void Function(ImportPhase phase);

abstract class ImportService {
  ImportPlatform get platform;
  Future<ImportDiscovery> text(String text, {ImportPhaseCallback? onPhase});
  Future<ImportDiscovery> link(
    String url, {
    bool useAi = false,
    ImportPhaseCallback? onPhase,
  });
  Future<ImportDiscovery> photos(
    List<ImportPhoto> photos, {
    ImportPhaseCallback? onPhase,
  });
  Future<Candidate> select(ImportDiscovery discovery, int index);
  Future<String> prompt();
  void cancel();
}

abstract interface class YoutubeWatchImport {
  Future<ImportDiscovery> watchAnyway(
    String url, {
    ImportPhaseCallback? onPhase,
  });
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
        SmartTextImportService,
        YoutubeWatchImport {
  NativeImportService({
    ImportPlatform? platform,
    this.existingTags,
    this.preferences,
    DraftStorage? diagnosticsStorage,
  }) : platform = platform ?? NativeImportPlatform(),
       _diagnostics = ImportDiagnosticsStore(diagnosticsStorage);
  @override
  final ImportPlatform platform;
  final List<String> Function()? existingTags;
  final LocalPreferences? preferences;
  final ImportDiagnosticsStore _diagnostics;
  final Map<String, AiReview> _reviews = {};
  final Map<String, List<String>> _warnings = {};
  int _epoch = 0;
  Operation? _operation;
  ({SocialImportPage page, List<String> ingredients})? _pendingWatch;
  void _check(int epoch) {
    if (_epoch != epoch) throw const ImportCancelled();
  }

  @override
  void cancel() {
    _epoch++;
    _pendingWatch = null;
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
    int epoch, {
    ImportPhaseCallback? onPhase,
  }) async {
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
      await task.setEffort(effort: settings.effort);
      var retry = false;
      while (true) {
        _check(epoch);
        final body = await task.request();
        _check(epoch);
        diagnostic.request(body);
        await _record(diagnostic, epoch);
        _check(epoch);
        if (!retry) onPhase?.call(ImportPhase.writing);
        _check(epoch);
        final reply = await platform.providerRequest(Uint8List.fromList(body));
        _check(epoch);
        onPhase?.call(ImportPhase.checking);
        diagnostic.reply(reply.status, reply.bytes);
        await _record(diagnostic, epoch);
        _check(epoch);
        final output = await task.accept(
          status: reply.status,
          bytes: reply.bytes,
        );
        _check(epoch);
        if (output is ProviderOutput_Retry) {
          retry = true;
          onPhase?.call(ImportPhase.retrying);
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
    String targetTitle = '',
  }) => ProviderInput(
    text: text,
    source: source,
    targetTitle: targetTitle,
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
  Recipe _source(Recipe recipe, String source, {String? sharedLink}) {
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
        notes: [
          if (f.notes.isNotEmpty) f.notes,
          if (sharedLink != null && sharedLink != source) sharedLink,
        ].join('\n'),
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
  Future<ImportDiscovery> text(
    String text, {
    ImportPhaseCallback? onPhase,
  }) async {
    final epoch = ++_epoch;
    if (utf8.encode(text).length > 5 * 1024 * 1024) {
      throw StateError('This file exceeds the 5 MB text import limit.');
    }
    onPhase?.call(ImportPhase.readingText);
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
    if (!settings.hasKey) {
      onPhase?.call(ImportPhase.readingText);
      return _basicText(text, epoch);
    }
    try {
      final output = await _extract(
        _input(text: text),
        settings,
        epoch,
        onPhase: onPhase,
      ) as ProviderOutput_Recipe;
      return ImportDiscovery(candidates: [_candidate(output.field0)]);
    } on ImportCancelled {
      rethrow;
    } catch (error) {
      _check(epoch);
      onPhase?.call(ImportPhase.readingText);
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

  ImportDiscovery _blocked(SocialSite site) => ImportDiscovery(
    candidates: const [],
    fallback: true,
    blockedSite: site,
    warnings: [blockedLinkMessage(site)],
  );

  Future<T> _youtubeRequest<T>(
    String mode,
    SmartImportSettings settings,
    Uint8List body,
    int epoch,
    FutureOr<T> Function(ProviderReply) read,
  ) async {
    _check(epoch);
    final diagnostic = AiImportDiagnostic(mode: mode, model: settings.model)
      ..request(body);
    try {
      await _record(diagnostic, epoch);
      _check(epoch);
      final reply = await platform.providerRequest(body);
      _check(epoch);
      diagnostic.reply(reply.status, reply.bytes);
      final result = await read(reply);
      _check(epoch);
      diagnostic.validation('Accepted');
      return result;
    } catch (error) {
      diagnostic.validation(
        error is VideoImportProblem ? error.message : _reason(error),
      );
      rethrow;
    } finally {
      await _record(diagnostic, epoch);
    }
  }

  Future<ImportDiscovery?> _descriptionRecipe(
    SocialImportPage post,
    YoutubeDescription decision,
    SmartImportSettings settings,
    int epoch,
    ImportPhaseCallback? onPhase,
  ) async {
    final video = post.videoUrl!;
    try {
      if (decision.kind == 'recipe') {
        final source = video.toString();
        final output = await _extract(
          _input(text: post.text, source: source, targetTitle: post.title),
          settings,
          epoch,
          onPhase: onPhase,
        ) as ProviderOutput_Recipe;
        final candidate = _candidate(_source(output.field0, source));
        if (candidate.recipe.fields.ingredients.isNotEmpty &&
            candidate.recipe.fields.steps.isNotEmpty) {
          return ImportDiscovery(
            candidates: [candidate],
            source: source,
            sourceLine: 'From the video description',
          );
        }
      } else if (decision.recipeLink case final target?
          when post.title.trim().isNotEmpty) {
        final result = await _website(
          target.toString(),
          true,
          epoch,
          onPhase,
          targetTitle: post.title,
          sharedVideo: video,
          settings: settings,
        );
        if (result.candidates.isNotEmpty) return result;
      }
    } on ImportCancelled {
      rethrow;
    } on Exception {
      _check(epoch);
    } on StateError {
      _check(epoch);
    }
    return null;
  }

  Future<ImportDiscovery> _youtube(
    Uri original,
    int epoch,
    ImportPhaseCallback? onPhase, {
    ImportPage? fetched,
    bool allowUnknownLength = false,
  }) async {
    ImportDiscovery problem(String message, {bool retry = false}) =>
        ImportDiscovery(
          candidates: const [],
          fallback: true,
          source: original.toString(),
          warnings: [message],
          needsYoutubeKey: message == youtubeKeyNeeded,
          canWatchAnyway:
              message == youtubeUnknownLength ||
              message == youtubeUnconfirmedVisibility,
          canRetryWatch: retry,
        );
    final settings = await platform.settings();
    _check(epoch);
    if (!settings.hasKey) return problem(youtubeKeyNeeded);
    const unavailable = 'cookdex couldn’t read this YouTube link.';
    if (canonicalYouTubeVideo(original) == null) return problem(unavailable);
    var watching = false;
    try {
      final pending = _pendingWatch;
      _pendingWatch = null;
      final SocialImportPage post;
      List<String> writtenIngredients = const [];
      if (allowUnknownLength &&
          pending != null &&
          pending.page.videoUrl == canonicalYouTubeVideo(original)) {
        post = pending.page;
        writtenIngredients = pending.ingredients;
      } else {
        onPhase?.call(ImportPhase.readingDescription);
        _check(epoch);
        final page = fetched ?? await platform.fetchPage(original.toString());
        _check(epoch);
        final uri = checkedImportUrl(page.url);
        if (!matchesSocialPostRedirect(original, uri)) {
          return problem(unavailable);
        }
        post = SocialImportPage.parse(SocialSite.youtube, uri, page.html);
        if (post.nonPublic) return problem(youtubeNotPublic);
        final video = post.videoUrl;
        if (post.blocked ||
            video == null ||
            canonicalYouTubeVideo(original) != video) {
          return problem(unavailable);
        }
        if (!post.unconfirmedVisibility) {
          final decision = await _youtubeRequest(
            'YouTube description',
            settings,
            youtubeDescriptionRequest(post.title, post.text, settings),
            epoch,
            (reply) {
              if (reply.status != 200) {
                throw VideoImportProblem(
                  reply.status == 401 || reply.status == 403
                      ? 'Gemini couldn’t authorize this request. Check your Gemini key.'
                      : 'Gemini couldn’t read the video description. Try again.',
                  retryable: true,
                );
              }
              return YoutubeDescription.read(reply, post.text);
            },
          );
          _check(epoch);
          writtenIngredients = decision.writtenIngredients;
          final result = await _descriptionRecipe(
            post,
            decision,
            settings,
            epoch,
            onPhase,
          );
          if (result != null) return result;
        }
      }
      _check(epoch);
      final video = post.videoUrl!;
      final source = video.toString();
      final seconds = post.seconds;
      if (seconds != null && seconds > youtubeWatchLimitMinutes * 60) {
        if (writtenIngredients.isNotEmpty && post.title.trim().isNotEmpty) {
          onPhase?.call(ImportPhase.writing);
          final candidate = await _youtubeRequest(
            'YouTube partial description',
            settings,
            youtubePartialRequest(
              post.title,
              post.text,
              writtenIngredients,
              settings,
            ),
            epoch,
            (reply) =>
                readPartialRecipe(reply, video, post.text, writtenIngredients),
          );
          if (candidate != null) {
            return ImportDiscovery(
              candidates: [candidate],
              warnings: candidate.warnings,
              source: source,
              sourceLine: 'From the video description',
            );
          }
        }
        return problem(youtubeTooLong);
      }
      if ((seconds == null || seconds <= 0 || post.unconfirmedVisibility) &&
          !allowUnknownLength) {
        _pendingWatch = (page: post, ingredients: writtenIngredients);
        return problem(
          seconds != null && seconds > 0
              ? youtubeUnconfirmedVisibility
              : youtubeUnknownLength,
        );
      }
      watching = true;
      onPhase?.call(ImportPhase.watchingVideo);
      _check(epoch);
      final watchChoice =
          preferences?.youtubeWatchModel ?? YoutubeWatchModel.flash;
      final watchSettings = SmartImportSettings(
        hasKey: settings.hasKey,
        model: watchChoice.modelId ?? settings.model,
        effort: settings.effort,
      );
      final body = youtubeWatchRequest(
        video,
        watchSettings,
        writtenIngredients,
        title: post.title,
        description: post.text,
      );
      final candidate = await _youtubeRequest(
        'YouTube video',
        watchSettings,
        body,
        epoch,
        (reply) {
          onPhase?.call(ImportPhase.writing);
          _check(epoch);
          return readWatchedRecipe(
            reply,
            video,
            seconds != null && seconds > 0
                ? seconds
                : youtubeWatchLimitMinutes * 60,
            writtenIngredients,
            description: post.text,
          );
        },
      );
      _check(epoch);
      return ImportDiscovery(
        candidates: [candidate],
        source: source,
        sourceLine: 'From watching the video',
        warnings: candidate.warnings,
      );
    } on ImportCancelled {
      rethrow;
    } on VideoImportProblem catch (error) {
      _check(epoch);
      return problem(error.message, retry: error.retryable);
    } on Exception {
      _check(epoch);
      return problem(watching ? youtubeUnclear : unavailable, retry: true);
    } on StateError {
      _check(epoch);
      return problem(watching ? youtubeUnclear : unavailable, retry: true);
    }
  }

  @override
  Future<ImportDiscovery> watchAnyway(
    String url, {
    ImportPhaseCallback? onPhase,
  }) {
    final uri = checkedImportUrl(url);
    if (canonicalYouTubeVideo(uri) == null) {
      throw const FormatException('Use a YouTube video link.');
    }
    return _youtube(uri, ++_epoch, onPhase, allowUnknownLength: true);
  }

  @override
  Future<ImportDiscovery> link(
    String url, {
    bool useAi = false,
    ImportPhaseCallback? onPhase,
  }) async {
    final epoch = ++_epoch;
    _pendingWatch = null;
    final original = checkedImportUrl(url);
    final checkedUrl = original.toString();
    final site = socialSite(original);
    if (site == SocialSite.youtube) return _youtube(original, epoch, onPhase);
    if (site != null) return _blocked(site);
    try {
      return await _website(checkedUrl, useAi, epoch, onPhase);
    } on YouTubeImportRedirect catch (redirect) {
      _check(epoch);
      return _youtube(redirect.url, epoch, onPhase);
    } on BlockedSocialImportUrl catch (error) {
      _check(epoch);
      return _blocked(error.site);
    }
  }

  Future<ImportDiscovery> _website(
    String checkedUrl,
    bool useAi,
    int epoch,
    ImportPhaseCallback? onPhase, {
    String targetTitle = '',
    Uri? sharedVideo,
    SmartImportSettings? settings,
  }) async {
    if (useAi) {
      settings ??= await platform.settings();
      _check(epoch);
      if (!settings.hasKey) {
        throw StateError('Add a Gemini key to use AI import.');
      }
    }
    onPhase?.call(
      sharedVideo == null
          ? ImportPhase.readingPage
          : ImportPhase.openingRecipePage,
    );
    ImportPage? page;
    var source = checkedUrl;
    try {
      final fetched = await platform.fetchPage(checkedUrl);
      _check(epoch);
      final uri = checkedImportUrl(fetched.url);
      final redirectedSite = socialSite(uri);
      if (sharedVideo != null && redirectedSite != null) {
        return const ImportDiscovery(candidates: []);
      }
      if (redirectedSite == SocialSite.youtube) {
        // A refusal from the subsequent video route belongs to that route.
        // ignore: unawaited_return_in_try_block
        return _youtube(uri, epoch, onPhase, fetched: fetched);
      }
      if (redirectedSite != null) return _blocked(redirectedSite);
      if (!isImportAccessWall(uri, fetched.html)) {
        page = fetched;
        source = uri.toString();
      }
    } on ImportPageRefused {
      _check(epoch);
    }
    if (page == null && !useAi) {
      final hasKey = (await platform.settings()).hasKey;
      _check(epoch);
      return ImportDiscovery(
        candidates: const [],
        fallback: true,
        websiteAiHint: hasKey,
        warnings: const ['This site didn’t share its recipe.'],
      );
    }
    if (settings != null) {
      final context = page == null ? '' : await pageAiContext(html: page.html);
      _check(epoch);
      final output = await _extract(
        _input(
          text: context,
          source: source,
          targetTitle: targetTitle,
          mode: page == null ? ProviderMode.urlRecipe : ProviderMode.recipe,
        ),
        settings,
        epoch,
        onPhase: onPhase,
      ) as ProviderOutput_Recipe;
      final candidate = _candidate(
        _source(output.field0, source, sharedLink: sharedVideo?.toString()),
      );
      if ((sharedVideo != null || page == null) &&
          (candidate.recipe.fields.ingredients.isEmpty ||
              candidate.recipe.fields.steps.isEmpty)) {
        return const ImportDiscovery(
          candidates: [],
          fallback: true,
          warnings: ['The recipe couldn’t be read from this page.'],
        );
      }
      return ImportDiscovery(
        candidates: [candidate],
        source: source,
        sourceLine: sharedVideo == null ? '' : 'From the creator’s recipe page',
      );
    }
    final parsed = await inspectPage(html: page!.html, url: source);
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
        if (parsed.candidates.isEmpty) 'No embedded recipe data was found.',
        if (incomplete)
          'Embedded recipe data is missing ingredients or directions.',
      ],
      source: source,
      websiteAiHint: parsed.candidates.isEmpty || incomplete,
    );
  }

  @override
  Future<ImportDiscovery> photos(
    List<ImportPhoto> photos, {
    ImportPhaseCallback? onPhase,
  }) async {
    final epoch = ++_epoch;
    onPhase?.call(ImportPhase.readingPhotos);
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
      onPhase: onPhase,
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
