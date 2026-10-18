import 'backup_feedback.dart';
import 'pixel_scroll.dart';
import 'retained_screen.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../app_platform.dart';
import '../app_identity.dart';
import '../local_preferences.dart';
import 'window_size.dart';
import '../src/rust/api.dart';
import 'components.dart';
import 'feedback.dart';
import '../cook_controller.dart';
import '../draft_storage.dart';
import '../editor_controller.dart';
import '../editor_model.dart';
import '../import_controller.dart';
import '../import_service.dart';
import 'import_screen.dart';
import 'text_import_review.dart';
import '../incoming_share.dart';
import 'recipe_editor.dart';
import 'recipe_detail.dart';
import '../recipe_store.dart';
import 'recipes_screen.dart';
import 'theme.dart';
import 'navigation_feedback.dart';
import 'shopping_screen.dart';
import '../export_service.dart';
import '../sync_controller.dart';
import '../settings_platform.dart';
import 'settings_screen.dart';
import 'snapshots_screen.dart' as snapshots;
import 'how_cookdex_works_screen.dart';
import '../sync_presentation.dart';
import 'sync_screen.dart';
import 'smart_settings_screen.dart';

class CookdexApp extends StatefulWidget {
  const CookdexApp({
    super.key,
    required this.store,
    required this.platform,
    this.drafts,
    this.importDrafts,
    this.importService,
    this.exportService,
  });
  final RecipeStore store;
  final AppPlatform platform;
  final DraftStorage? drafts;
  final DraftStorage? importDrafts;
  final ImportService? importService;
  final ExportService? exportService;

  @override
  State<CookdexApp> createState() => _CookdexAppState();
}

class _CookdexAppState extends State<CookdexApp> with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  final _recipesNavigator = GlobalKey<NavigatorState>();
  late final ExportService _exports = widget.exportService ?? ExportService();
  final _settingsPlatform = SettingsPlatform();
  late final _installedVersion = _settingsPlatform.appVersion();
  late final SyncController? _sync = syncForStore(
    widget.store,
    widget.platform.isAndroid,
    _settingsPlatform.requestLocalNetwork,
    _settingsPlatform.hasLocalNetwork,
  );
  late final ImportService _smart =
      widget.importService ??
      NativeImportService(
        existingTags: () =>
            widget.store.summaries.expand((r) => r.tags).toSet().toList(),
      );
  CoreSession? get _session => widget.store.repository is RustRecipeRepository
      ? (widget.store.repository as RustRecipeRepository).session
      : null;
  late final ScrollController _recipesScroll;
  late final CookController _cook;
  late final _OverlayObserver _observer;
  int _tab = 0;
  String? _selected;
  Set<String>? _selection;
  bool _selectionBusy = false;
  bool _importOpen = false;
  bool _returnToSender = false;
  late final IncomingShares _incoming = IncomingShares(onReady: _drainShares);

  bool _resumed = true;
  bool _obscured = false;
  bool _restoring = false;
  bool _snapshotsFailing = false;
  bool _snapshotCheckRunning = false;
  Timer? _snapshotTimer;
  bool _openingEditor = false;
  late final DraftStorage _drafts = widget.drafts ?? MemoryDraftStorage();
  late final DraftStorage _importDrafts =
      widget.importDrafts ?? MemoryDraftStorage();
  ColorScheme? _wallpaper;
  ColorScheme? _lightWallpaper;
  bool _wallpaperEnabled = false;
  int _wallpaperRequest = 0;
  bool _keyboardVisible = false;
  double? _tabBackProgress;
  bool _backFromRight = false;
  bool _keyboardBack = false;
  int? _gestureTab;
  double _cookFooterHeight = 64;

  @override
  void initState() {
    super.initState();
    if (widget.platform.isAndroid) _incoming.start();
    unawaited(_maintainSnapshots());
    _snapshotTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_resumed) unawaited(_maintainSnapshots());
    });
    unawaited(_sync?.lifecycle(true));
    _recipesScroll = PixelScrollController(
      initialScrollOffset: widget.store.preferences.scrollOffset,
    );
    WidgetsBinding.instance.addObserver(this);
    _cook = CookController(
      preferences: widget.store.preferences,
      setWake: widget.platform.setKeepScreenOn,
    );
    _observer = _OverlayObserver((obscured) {
      _obscured = obscured;
      _updateVisibility();
      if (!obscured) _drainShares();
    });
    widget.store.preferences.addListener(_preferencesChanged);
    _preferencesChanged();
  }

  void _openHelp(BuildContext context) {
    Navigator.of(context, rootNavigator: true).push<void>(
      cookdexRoute<void>(
        context,
        builder: (_) => HowCookdexWorksScreen(
          loadAppInfo: _settingsPlatform.appInfo,
          openUrl: widget.platform.openSource,
        ),
      ),
    );
  }

  void _openSyncIndicator(BuildContext context) {
    final sync = _sync;
    if (sync != null &&
        syncPresentation(sync, widget.store.conflicts.length).label ==
            'Sync conflict') {
      Navigator.of(context, rootNavigator: true).push<void>(
        cookdexRoute<void>(
          context,
          builder: (_) =>
              ConflictsScreen(controller: sync, store: widget.store),
        ),
      );
    } else {
      _openSync(context);
    }
  }

  void _openSync(BuildContext context) {
    if (_sync != null) {
      Navigator.of(context, rootNavigator: true).push<void>(
        cookdexRoute<void>(
          context,
          builder: (_) => SyncScreen(controller: _sync, store: widget.store),
        ),
      );
    }
  }

  Future<void> _manualSync(BuildContext context) async {
    if (_sync == null || _sync.status?.enabled != true) {
      _openSync(context);
      return;
    }
    await _sync.manual();
    if (context.mounted && _sync.error != null) {
      showFeedback(context, _sync.error!, kind: FeedbackKind.error);
    }
  }

  void _preferencesChanged() {
    final enabled =
        widget.platform.isAndroid && widget.store.preferences.wallpaperColors;
    if (enabled != _wallpaperEnabled) {
      _wallpaperEnabled = enabled;
      if (enabled) {
        unawaited(_refreshWallpaper());
      } else {
        ++_wallpaperRequest;
      }
    }
    _updateVisibility();
    if (mounted) setState(() {});
  }

  Future<void> _refreshWallpaper() async {
    if (!_wallpaperEnabled) return;
    final request = ++_wallpaperRequest;
    try {
      final values = await Future.wait([
        widget.platform.wallpaperColorScheme(),
        widget.platform.wallpaperColorScheme(brightness: Brightness.light),
      ]);
      if (!mounted || request != _wallpaperRequest) return;
      setState(() {
        _wallpaper = values[0];
        _lightWallpaper = values[1];
      });
    } catch (_) {
      // Keep the last usable palette; resume or re-enabling retries the read.
    }
  }

  @override
  void didChangeMetrics() {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final visible = view.viewInsets.bottom > 0;
    if (_keyboardVisible && !visible) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    _keyboardVisible = visible;
    if (mounted) setState(() {});
  }

  @override
  Future<bool> didPopRoute() async {
    if (!_keyboardVisible) return false;
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    return true;
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent event) {
    _keyboardBack = _keyboardVisible;
    if (_keyboardBack) return true;
    if (_tab == 0 || _obscured) return false;
    _gestureTab = _tab;
    setState(() {
      _tabBackProgress = event.progress;
      _backFromRight = event.swipeEdge == SwipeEdge.right;
    });
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent event) {
    if (_gestureTab != null && _gestureTab == _tab && !_obscured) {
      setState(() => _tabBackProgress = event.progress);
    }
  }

  @override
  void handleCancelBackGesture() {
    _keyboardBack = false;
    _gestureTab = null;
    setState(() => _tabBackProgress = null);
  }

  @override
  void handleCommitBackGesture() {
    final keyboard = _keyboardBack;
    final tab = _gestureTab;
    handleCancelBackGesture();
    if (keyboard) {
      unawaited(didPopRoute());
    } else if (tab != null && tab == _tab && !_obscured) {
      unawaited(_back());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed) {
      _drainShares();
      unawaited(_refreshWallpaper());
      unawaited(_maintainSnapshots());
    }
    unawaited(_sync?.lifecycle(_resumed));
    _updateVisibility();
  }

  void _updateVisibility() {
    _cook.setShoppingVisible(
      _tab == 1 && widget.store.preferences.shoppingKeepAwake,
    );
    _cook.setVisibility(
      visible: _tab == 0 && _selected != null,
      resumed: _resumed,
      obscured: _obscured,
    );
  }

  void _openRecipe(String id) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _selected = id);
    _updateVisibility();
  }

  void _closeRecipe() {
    setState(() => _selected = null);
    _cook.setRecipe(null);
    _updateVisibility();
  }

  void _selectTab(int index) {
    _gestureTab = null;
    _tabBackProgress = null;
    FocusManager.instance.primaryFocus?.unfocus();
    if (index == 0 && _tab == 0) {
      if (_selected != null) {
        _closeRecipe();
      } else if (_recipesScroll.hasClients) {
        _recipesScroll.jumpTo(0);
      }
    }
    setState(() => _tab = index);
    _updateVisibility();
  }

  Future<void> _back() async {
    if (FocusManager.instance.primaryFocus?.hasFocus == true &&
        _navigator.currentContext != null &&
        MediaQuery.viewInsetsOf(_navigator.currentContext!).bottom > 0) {
      FocusManager.instance.primaryFocus?.unfocus();
      return;
    }
    if (_tab != 0) {
      _selectTab(0);
    } else if (_selection != null) {
      setState(() => _selection = null);
    } else if (_selected != null) {
      await _recipesNavigator.currentState?.maybePop();
    } else if (widget.store.preferences.query.isNotEmpty) {
      widget.store.preferences.setQuery('');
    } else if (widget.platform.isAndroid) {
      await widget.platform.backgroundTask();
    }
  }

  Future<void> _add(BuildContext context) async {
    final choice = await showCookdexSheet<String>(
      context,
      child: Builder(
        builder: (sheetContext) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Symbols.edit_note),
              title: const Text('Write a recipe'),
              onTap: () => Navigator.pop(sheetContext, 'Recipe editing'),
            ),
            ListTile(
              leading: const Icon(Symbols.file_upload),
              title: const Text('Smart Import'),
              onTap: () => Navigator.pop(sheetContext, 'Recipe import'),
            ),
          ],
        ),
      ),
    );
    if (choice != null && context.mounted) {
      if (choice == 'Recipe editing') {
        await _openEditor(context);
      } else {
        await _openImport(context);
      }
    }
  }

  Future<Recipe?> _openEditor(
    BuildContext context, {
    String? recipeId,
    Candidate? imported,
    bool exactTextImport = false,
  }) async {
    if (recipeId != null &&
        widget.store.conflicts.any((c) => c.recipeId == recipeId)) {
      _openSync(context);
      showFeedback(
        context,
        'Resolve this recipe’s conflict before editing.',
        kind: FeedbackKind.error,
      );
      return null;
    }
    if (_openingEditor) return null;
    _openingEditor = true;
    EditorController? controller;
    try {
      Map<String, dynamic>? savedDraft;
      try {
        savedDraft = await _drafts.read();
        if (savedDraft != null) EditorDraft.fromJson(savedDraft);
      } catch (_) {
        if (!context.mounted) return null;
        if (!await confirmCookdex(
          context,
          title: 'Discard unreadable draft?',
          action: 'Discard',
          destructive: true,
        )) {
          return null;
        }
        await _drafts.clear();
        savedDraft = null;
      }
      if (!context.mounted) return null;
      Map<String, dynamic>? recovered;
      if (savedDraft != null) {
        final choice = await showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Resume draft?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(dialogContext).colorScheme.error,
                ),
                onPressed: () => Navigator.pop(dialogContext, 'discard'),
                child: const Text('Discard'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, 'resume'),
                child: const Text('Resume'),
              ),
            ],
          ),
        );
        if (choice == null || !context.mounted) return null;
        if (choice == 'resume') {
          recovered = savedDraft;
        } else {
          await _drafts.clear();
        }
      }
      Recipe? base;
      if (recovered == null && recipeId != null) {
        base = await widget.store.detail(recipeId);
        if (base == null) {
          throw StateError('This recipe is no longer available.');
        }
      }
      controller = await EditorController.create(
        store: widget.store,
        storage: _drafts,
        base: base,
        recovered: recovered,
        imported: recovered == null ? imported : null,
        exactTextImport: exactTextImport,
      );
      if (!context.mounted) return null;
      final saved = await Navigator.of(context, rootNavigator: true)
          .push<Recipe>(
            cookdexRoute<Recipe>(
              context,
              builder: (_) => RecipeEditor(
                controller: controller!,
                tagSuggestions: widget.store.summaries
                    .expand((r) => r.tags)
                    .toSet()
                    .toList(),
                ingredientSuggestions: widget.store.summaries
                    .expand((r) => r.ingredients)
                    .toSet()
                    .toList(),
              ),
            ),
          );
      if (saved != null && mounted) {
        if (imported == null) _openRecipe(saved.id);
      }
      // Resuming an older draft is independent of the pending import input.
      // Return to Import without clearing its text/photos after that save.
      return imported != null && recovered != null ? null : saved;
    } catch (error) {
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Could not open editor'),
            content: Text(
              error is ServiceError ? error.message : error.toString(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }
    } finally {
      controller?.dispose();
      _openingEditor = false;
      _drainShares();
    }
    return null;
  }

  Future<void> _openImport(
    BuildContext context, {
    IncomingShare? incoming,
  }) async {
    if (_importOpen) return;
    _importOpen = true;
    _returnToSender |= incoming?.coldStart == true;
    final controller = ImportController(
      service:
          widget.importService ??
          NativeImportService(
            existingTags: () =>
                widget.store.summaries.expand((r) => r.tags).toSet().toList(),
          ),
      storage: incoming == null ? _importDrafts : MemoryDraftStorage(),
      preferences: widget.store.preferences,
    );
    try {
      final saved = await Navigator.of(context, rootNavigator: true)
          .push<Recipe>(
            cookdexRoute<Recipe>(
              context,
              builder: (_) => ImportScreen(
                controller: controller,
                initialInput: incoming == null
                    ? null
                    : (c) => incoming.apply(c),
                onReview: (context, candidate) =>
                    _openEditor(context, imported: candidate),
                onTextReview: (context, candidate) => _openEditor(
                  context,
                  imported: candidate,
                  exactTextImport: true,
                ),
                onTextBatch: (context, blocks) =>
                    Navigator.of(context).push<Recipe>(
                      cookdexRoute<Recipe>(
                        context,
                        builder: (_) => TextImportReview(
                          blocks: blocks,
                          store: widget.store,
                          service: controller.service,
                          onReview: (context, candidate) => _openEditor(
                            context,
                            imported: candidate,
                            exactTextImport: true,
                          ),
                        ),
                      ),
                    ),
              ),
            ),
          );
      if (saved != null && mounted) {
        _returnToSender = false;
        _openRecipe(saved.id);
      }
      if (saved == null &&
          _returnToSender &&
          mounted &&
          await _incoming.finishIfEmpty()) {
        _returnToSender = false;
      }
    } finally {
      controller.dispose();
      _importOpen = false;
      _drainShares();
    }
  }

  void _drainShares() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _openingEditor || _importOpen || _obscured || !_resumed) {
        return;
      }
      final incoming = _incoming.take();
      final context = _navigator.currentState?.overlay?.context;
      if (incoming != null && context != null) {
        await _openImport(context, incoming: incoming);
      } else if (_returnToSender && await _incoming.finishIfEmpty()) {
        _returnToSender = false;
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _selectionAction(
    BuildContext context, {
    bool shopping = false,
  }) async {
    if (_selectionBusy || _selection?.isNotEmpty != true) return;
    setState(() => _selectionBusy = true);
    final ids = _selection!.toList();
    try {
      final generation = widget.store.generation;
      final recipes = <Recipe>[];
      for (final id in ids) {
        final recipe = await widget.store.detail(id);
        if (recipe == null || generation != widget.store.generation) {
          throw StateError('Recipes changed. Select them again.');
        }
        recipes.add(recipe);
      }
      if (!context.mounted) return;
      if (shopping) {
        var added = 0;
        try {
          for (final recipe in recipes) {
            await widget.store.addShopping(
              recipe.id,
              List.generate(recipe.fields.ingredients.length, (i) => i),
            );
            added++;
            _selection?.remove(recipe.id);
          }
        } catch (_) {
          throw StateError(
            'Added $added of ${recipes.length} recipes. The remaining recipes are still selected.',
          );
        }
        if (context.mounted) {
          showFeedback(
            context,
            'Added ${recipes.length} recipes to shopping list',
          );
        }
        if (mounted) setState(() => _selection = null);
      } else {
        final action = await showShareOptions(
          context,
          isAndroid: widget.platform.isAndroid,
        );
        if (action != null && context.mounted) {
          await _export(context, () => _exports.recipes(recipes, action));
        }
      }
    } catch (error) {
      if (context.mounted) {
        showFeedback(
          context,
          error is StateError
              ? error.message.toString()
              : 'Could not complete this action.',
          kind: FeedbackKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _selectionBusy = false);
    }
  }

  Future<void> _recipeActions(BuildContext context, RecipeSummary recipe) =>
      showRecipeActions(
        context: context,
        store: widget.store,
        recipe: recipe,
        onDeleted: _selected == recipe.id ? _closeRecipe : null,
        onEdit: () => _openEditor(context, recipeId: recipe.id),
        onAction: (action) => _recipeAction(context, recipe.id, action),
      );

  Future<void> _recipeAction(
    BuildContext context,
    String id,
    String action,
  ) async {
    if (action == 'select') {
      _closeRecipe();
      setState(() {
        _tab = 0;
        _selection = {id};
      });
      return;
    }
    try {
      final recipe = await widget.store.detail(id);
      if (recipe == null || !context.mounted) return;
      if (action == 'shopping') {
        await showShoppingSelection(
          context,
          widget.store,
          recipe,
          scale: _selected == id ? _cook.scale : 2,
        );
        return;
      }
      final exportAction = await showShareOptions(
        context,
        isAndroid: widget.platform.isAndroid,
      );
      if (exportAction == null || !context.mounted) return;
      await _export(context, () => _exports.recipe(recipe, exportAction));
    } catch (error) {
      if (context.mounted) {
        showFeedback(
          context,
          error is ServiceError
              ? error.message
              : 'Could not complete this action.',
          kind: FeedbackKind.error,
        );
      }
    }
  }

  Future<void> _export(
    BuildContext context,
    Future<ExportOutcome> Function() run, {
    Future<void> Function()? onSaved,
  }) async {
    try {
      final result = await run();
      if (!context.mounted ||
          result == ExportOutcome.cancelled ||
          result == ExportOutcome.shareOpened) {
        return;
      }
      if (result == ExportOutcome.saved && onSaved != null) {
        await onSaved();
        return;
      }
      showFeedback(context, switch (result) {
        ExportOutcome.copied => 'Copied text',
        ExportOutcome.copiedFallback => 'Sharing unavailable; copied text',
        _ => 'Text saved',
      });
    } catch (error) {
      if (context.mounted) {
        final message = error is StateError
            ? error.message.toString()
            : error is PlatformException
            ? error.message ?? 'Could not export text. Try again.'
            : 'Could not export text. Try again.';
        showFeedback(context, message, kind: FeedbackKind.error);
      }
    }
  }

  Future<void> _saveCookbook(BuildContext context) async {
    final generation = widget.store.generation;
    final omitted = widget.store.setAsideCount;
    final summaries = List.of(widget.store.summaries);
    await _export(context, () async {
      final recipes = <Recipe>[];
      for (final summary in summaries) {
        final recipe = await widget.store.detail(summary.id);
        if (widget.store.generation != generation || recipe == null) {
          throw StateError('Recipes changed. Try saving the cookbook again.');
        }
        recipes.add(recipe);
      }
      return _exports.cookbook(recipes);
    }, onSaved: () => showCookbookSaved(context, omitted));
  }

  Future<void> _settingsAction(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    setState(() => _restoring = true);
    try {
      await action();
      await widget.store.refresh();
    } catch (e) {
      if (context.mounted) {
        showFeedback(
          context,
          e is ServiceError
              ? e.message
              : 'The action could not finish. Refresh and try again.',
          kind: FeedbackKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Future<void> _maintainSnapshots() async {
    if (_snapshotCheckRunning || _session == null) return;
    _snapshotCheckRunning = true;
    try {
      final failing = await _session!.rollingSnapshotMaintenance();
      if (mounted && _snapshotsFailing != failing) {
        setState(() => _snapshotsFailing = failing);
      }
    } catch (_) {
      // Background backup errors must never interfere with recipe actions.
    } finally {
      _snapshotCheckRunning = false;
    }
  }

  Future<void> _openSnapshots(BuildContext context) async {
    await Navigator.of(context, rootNavigator: true).push<void>(
      cookdexRoute<void>(
        context,
        builder: (snapshotContext) => snapshots.SnapshotsScreen(
          load: () async {
            final listing = await _session!.rollingSnapshots();
            return snapshots.SnapshotListing(
              repeatedlyFailing: listing.repeatedlyFailing,
              entries: listing.entries
                  .map(
                    (e) => snapshots.LocalSnapshotEntry(
                      id: e.id,
                      createdAt: DateTime.parse(e.createdAt),
                      recipeCount: e.recipeCount,
                      omittedCount: e.omittedCount,
                      reason: e.reason,
                    ),
                  )
                  .toList(),
            );
          },
          onRestore: (entry) async {
            final bytes = await _session!.rollingSnapshotBytes(id: entry.id);
            if (snapshotContext.mounted) {
              await _restore(snapshotContext, snapshotBytes: bytes);
            }
          },
          onExport: (entry) async {
            final bytes = await _session!.rollingSnapshotBytes(id: entry.id);
            final saved = await _settingsPlatform.saveZip(bytes);
            if (saved && snapshotContext.mounted) {
              await showBackupSaved(snapshotContext, entry.omittedCount);
            }
          },
        ),
      ),
    );
  }

  Future<void> _backup(BuildContext context) =>
      _settingsAction(context, () async {
        final report = await _session!.backupReport(operation: Operation());
        final saved = await _settingsPlatform.saveZip(report.bytes);
        if (!saved || !context.mounted) return;
        await showBackupSaved(context, report.omitted);
      });
  Future<void> _cleanup(
    BuildContext context,
  ) => _settingsAction(context, () async {
    final preview = await _session!.previewCleanup();
    final changed = await preview.changed();
    final skipped = await preview.skippedConflicts();
    if (!context.mounted) return;
    if (changed == 0) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Clean up recipes'),
          content: Text(
            'No recipes need cleanup.\n$skipped conflicted recipes skipped.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      return;
    }
    if (!await confirmCookdex(
      context,
      title: 'Clean up $changed recipes?',
      action: 'Clean up',
      content: Text(
        'Normalize units, times and lowercase tags.\n$skipped conflicted recipes will be skipped.',
      ),
    )) {
      return;
    }
    await _session!.cleanup(preview: preview, operation: Operation());
    if (context.mounted) showFeedback(context, '$changed recipes cleaned up');
  });
  Future<void> _recover(BuildContext context) =>
      _settingsAction(context, () async {
        final generation = widget.store.generation;
        if (!await confirmCookdex(
          context,
          title: 'Recover previous save?',
          action: 'Recover',
          content: const Text(
            'Restore the previous Flutter recipe collection and shopping list.',
          ),
        )) {
          return;
        }
        await _session!.recover(generation: generation, operation: Operation());
      });
  Future<void> _restore(
    BuildContext context, {
    Uint8List? snapshotBytes,
  }) async {
    if (_restoring) return;
    setState(() => _restoring = true);
    try {
      final bytes = snapshotBytes ?? await widget.platform.pickRecipeZip();
      if (bytes == null) return;
      final preview = await widget.store.previewRestore(bytes);
      if (!context.mounted) return;
      final report = preview.report;
      if (!await confirmRestore(context, report)) return;
      final restored = await widget.store.restoreBackup(preview);
      if (!context.mounted) return;
      final clean = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Recipes restored'),
          content: Text(
            '${restored.added} added · ${restored.updated} updated · ${restored.skipped} skipped'
            '${restored.conflicts.isEmpty ? '' : '\n${restored.conflicts.length} ${restored.conflicts.length == 1 ? 'conflict' : 'conflicts'} kept unchanged.'}',
          ),
          actions: [
            if (_session != null)
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Clean up recipes'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (clean == true && context.mounted) await _cleanup(context);
    } catch (error) {
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Could not restore ZIP'),
            content: Text(
              error is ServiceError
                  ? error.message
                  : 'The recipe backup could not be opened or restored.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  void dispose() {
    _incoming.dispose();
    _snapshotTimer?.cancel();
    _sync?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    widget.store.preferences.removeListener(_preferencesChanged);
    _recipesScroll.dispose();
    _cook.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    scrollBehavior: const CookdexScrollBehavior(),
    title: appName,
    debugShowCheckedModeBanner: false,
    navigatorKey: _navigator,
    navigatorObservers: [_observer],
    themeMode: widget.store.preferences.themeMode,
    theme: cookdexTheme(
      colors:
          widget.platform.isAndroid && widget.store.preferences.wallpaperColors
          ? _lightWallpaper ?? cookdexLightColors
          : cookdexLightColors,
    ),
    darkTheme: cookdexTheme(
      colors:
          widget.platform.isAndroid && widget.store.preferences.wallpaperColors
          ? _wallpaper
          : null,
    ),
    themeAnimationDuration:
        WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 150),
    builder: (context, child) => ListenableBuilder(
      listenable: _cook,
      child: child,
      builder: (context, child) => Theme(
        data: cookdexTheme(
          largerBody: WindowSizeClass.of(context) != WindowSizeClass.compact,
          snackBarBottomInset:
              WindowSizeClass.of(context) == WindowSizeClass.expanded &&
                  _tab == 0 &&
                  _selected != null &&
                  _cook.active
              ? _cookFooterHeight + 16
              : null,
          colors: Theme.of(context).colorScheme,
        ),
        child: Actions(
          actions: {
            EditableTextTapOutsideIntent:
                CallbackAction<EditableTextTapOutsideIntent>(
                  onInvoke: (intent) {
                    intent.focusNode.unfocus();
                    return null;
                  },
                ),
          },
          child: child!,
        ),
      ),
    ),
    home: RetainedScreen(
      child: Builder(
        builder: (context) => PopScope(
          canPop:
              _tab == 0 &&
              _selected == null &&
              _selection == null &&
              widget.store.preferences.query.isEmpty &&
              !_keyboardVisible,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) unawaited(_back());
          },
          child: Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
            },
            child: Actions(
              actions: {
                DismissIntent: CallbackAction<DismissIntent>(
                  onInvoke: (_) {
                    unawaited(_navigator.currentState!.maybePop());
                    return null;
                  },
                ),
              },
              child: Scaffold(
                body: Row(
                  children: [
                    if (WindowSizeClass.of(context) ==
                            WindowSizeClass.expanded &&
                        MediaQuery.viewInsetsOf(context).bottom == 0)
                      ListenableBuilder(
                        listenable: widget.store,
                        builder: (context, _) => NavigationRail(
                          selectedIndex: _tab,
                          groupAlignment: 0.0,
                          onDestinationSelected: _selectTab,
                          labelType: NavigationRailLabelType.all,
                          destinations: [
                            NavigationRailDestination(
                              icon: const Icon(Symbols.menu_book),
                              selectedIcon: const Icon(
                                Symbols.menu_book,
                                fill: 1,
                              ),
                              label: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 120,
                                ),
                                child: const Text(
                                  'Recipes',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                            NavigationRailDestination(
                              icon: Badge(
                                isLabelVisible:
                                    widget.store.uncheckedShoppingCount > 0,
                                label: Text(
                                  '${widget.store.uncheckedShoppingCount}',
                                ),
                                child: const Icon(Symbols.shopping_cart),
                              ),
                              selectedIcon: Badge(
                                isLabelVisible:
                                    widget.store.uncheckedShoppingCount > 0,
                                label: Text(
                                  '${widget.store.uncheckedShoppingCount}',
                                ),
                                child: const Icon(
                                  Symbols.shopping_cart,
                                  fill: 1,
                                ),
                              ),
                              label: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 120,
                                ),
                                child: const Text(
                                  'Shopping list',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                            NavigationRailDestination(
                              icon: const Icon(Symbols.settings),
                              selectedIcon: const Icon(
                                Symbols.settings,
                                fill: 1,
                              ),
                              label: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 120,
                                ),
                                child: const Text(
                                  'Settings',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: RetainedTabTransition(
                        index: _tab,
                        backProgress: _tabBackProgress,
                        backFromRight: _backFromRight,
                        children: [
                          Navigator(
                            key: _recipesNavigator,
                            onDidRemovePage: (page) {
                              if (page.name == _selected) _closeRecipe();
                            },
                            pages: [
                              OpaqueMaterialPage<void>(
                                key: const ValueKey('recipes-root'),
                                child: SafeArea(
                                  bottom: false,
                                  child: RecipesScreen(
                                    selectedIds: _selection,
                                    onToggleSelection: _selectionBusy
                                        ? null
                                        : (id) => setState(() {
                                            if (!_selection!.remove(id)) {
                                              _selection!.add(id);
                                            }
                                          }),
                                    onCloseSelection: _selectionBusy
                                        ? null
                                        : () =>
                                              setState(() => _selection = null),
                                    onSelectAll: _selectionBusy
                                        ? null
                                        : () => setState(
                                            () => _selection = widget
                                                .store
                                                .visibleRecipes
                                                .map((r) => r.id)
                                                .toSet(),
                                          ),
                                    onShareSelection: _selectionBusy
                                        ? null
                                        : () => _selectionAction(context),
                                    onShoppingSelection: _selectionBusy
                                        ? null
                                        : () => _selectionAction(
                                            context,
                                            shopping: true,
                                          ),
                                    store: widget.store,
                                    preferences: widget.store.preferences,
                                    controller: _recipesScroll,
                                    onOpenRecipe: _openRecipe,
                                    onAdd: () => _add(context),
                                    onWrite: () => _openEditor(context),
                                    onImport: () => _openImport(context),
                                    onSync: () => _manualSync(context),
                                    syncController: _sync,
                                    onSyncStatus: () =>
                                        _openSyncIndicator(context),
                                    onHelp: () => _openHelp(context),
                                    onRestore: () => _restore(context),
                                    onActions: (recipe) =>
                                        _recipeActions(context, recipe),
                                  ),
                                ),
                              ),
                              if (_selected != null)
                                OpaqueMaterialPage<void>(
                                  key: ValueKey(_selected),
                                  name: _selected,
                                  child: PopScope(
                                    canPop: _tab == 0,
                                    child: SafeArea(
                                      bottom: false,
                                      child: RecipeTextScale(
                                        factor: widget
                                            .store
                                            .preferences
                                            .recipeTextSize
                                            .factor,
                                        child: RecipeDetail(
                                          key: ValueKey(_selected),
                                          store: widget.store,
                                          recipeId: _selected!,
                                          cook: _cook,
                                          onControlsHeight: (height) {
                                            if (mounted &&
                                                _cookFooterHeight != height) {
                                              setState(
                                                () =>
                                                    _cookFooterHeight = height,
                                              );
                                            }
                                          },
                                          showControls:
                                              WindowSizeClass.of(context) ==
                                              WindowSizeClass.expanded,
                                          onBack: () => _recipesNavigator
                                              .currentState
                                              ?.maybePop(),
                                          onActions: () {
                                            final recipe = widget
                                                .store
                                                .summaries
                                                .where((r) => r.id == _selected)
                                                .firstOrNull;
                                            if (recipe != null) {
                                              _recipeActions(context, recipe);
                                            }
                                          },
                                          onEdit: () => _openEditor(
                                            context,
                                            recipeId: _selected,
                                          ),
                                          onSource: widget.platform.openSource,
                                          onAddToShopping: () => _recipeAction(
                                            context,
                                            _selected!,
                                            'shopping',
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          ShoppingScreen(
                            store: widget.store,
                            onSaveText: (shoppingContext) => _export(
                              shoppingContext,
                              () => _exports.shopping(
                                widget.store.shopping,
                                widget.store.summaries,
                              ),
                            ),
                          ),
                          SettingsScreen(
                            hasPrevious: widget.store.hasPrevious,
                            busy: _restoring,
                            syncSummary:
                                '${_sync?.summary ?? 'Off'}${widget.store.conflicts.isEmpty ? '' : ' · ${widget.store.conflicts.length} conflicts'}',
                            syncChanges: _sync,
                            readSyncSummary: () =>
                                '${_sync?.summary ?? 'Off'}${widget.store.conflicts.isEmpty ? '' : ' · ${widget.store.conflicts.length} conflicts'}',
                            onSync: _sync == null
                                ? null
                                : () => _openSync(context),
                            onDownloadRecipeZip: _session == null
                                ? null
                                : () => _backup(context),
                            onRestoreRecipeZip: () => _restore(context),
                            onSnapshots: _session == null
                                ? null
                                : () => _openSnapshots(context),
                            snapshotsFailing: _snapshotsFailing,
                            onRecoverPreviousSave: _session == null
                                ? null
                                : () => _recover(context),
                            onCleanUpRecipes: _session == null
                                ? null
                                : () => _cleanup(context),
                            onSaveReadableCookbook: () =>
                                _saveCookbook(context),
                            onSmartImportSettings: () =>
                                Navigator.of(
                                  context,
                                  rootNavigator: true,
                                ).push<void>(
                                  cookdexRoute<void>(
                                    context,
                                    builder: (_) => SmartSettingsScreen(
                                      service: _smart,
                                      testKey: () => _settingsPlatform.testKey(
                                        _smart.platform,
                                      ),
                                      openUrl: widget.platform.openSource,
                                    ),
                                  ),
                                ),
                            shoppingKeepAwake:
                                widget.store.preferences.shoppingKeepAwake,
                            onShoppingKeepAwake:
                                widget.store.preferences.setShoppingKeepAwake,
                            recipeTextScale:
                                widget.store.preferences.recipeTextSize.factor,
                            onRecipeTextScale: (factor) =>
                                widget.store.preferences.setRecipeTextSize(
                                  RecipeTextSize.values.firstWhere(
                                    (s) => s.factor == factor,
                                  ),
                                ),
                            isAndroid: widget.platform.isAndroid,
                            themeMode: widget.store.preferences.themeMode,
                            onThemeMode: widget.store.preferences.setThemeMode,
                            wallpaperColors:
                                widget.store.preferences.wallpaperColors,
                            onWallpaperColors:
                                widget.store.preferences.setWallpaperColors,
                            version: 'Version unavailable',
                            installedVersion: _installedVersion,
                            onHowCookdexWorks: () => _openHelp(context),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                bottomNavigationBar: ListenableBuilder(
                  listenable: Listenable.merge([_cook, widget.store]),
                  builder: (context, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (WindowSizeClass.of(context) !=
                              WindowSizeClass.expanded &&
                          _tab == 0 &&
                          _selected != null &&
                          _cook.active)
                        RecipeTextScale(
                          factor:
                              widget.store.preferences.recipeTextSize.factor,
                          child: CookNavigation(
                            cook: _cook,
                            includeBottomInset: false,
                          ),
                        ),
                      if (WindowSizeClass.of(context) !=
                              WindowSizeClass.expanded &&
                          MediaQuery.viewInsetsOf(context).bottom == 0)
                        NavigationBar(
                          selectedIndex: _tab,
                          onDestinationSelected: _selectTab,
                          destinations: [
                            NavigationDestination(
                              icon: const Icon(Symbols.menu_book),
                              selectedIcon: const Icon(
                                Symbols.menu_book,
                                fill: 1,
                              ),
                              label: 'Recipes',
                            ),
                            NavigationDestination(
                              icon: Badge(
                                isLabelVisible:
                                    widget.store.uncheckedShoppingCount > 0,
                                label: Text(
                                  '${widget.store.uncheckedShoppingCount}',
                                ),
                                child: const Icon(Symbols.shopping_cart),
                              ),
                              selectedIcon: Badge(
                                isLabelVisible:
                                    widget.store.uncheckedShoppingCount > 0,
                                label: Text(
                                  '${widget.store.uncheckedShoppingCount}',
                                ),
                                child: const Icon(
                                  Symbols.shopping_cart,
                                  fill: 1,
                                ),
                              ),
                              label: 'Shopping list',
                            ),
                            NavigationDestination(
                              icon: const Icon(Symbols.settings),
                              selectedIcon: const Icon(
                                Symbols.settings,
                                fill: 1,
                              ),
                              label: 'Settings',
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _OverlayObserver extends NavigatorObserver {
  _OverlayObserver(this.changed);
  final void Function(bool) changed;
  final Set<Route<dynamic>> _routes = {};
  void _notify() => scheduleMicrotask(() => changed(_routes.length > 1));
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _notify();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _notify();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _notify();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _routes.remove(oldRoute);
    if (newRoute != null) _routes.add(newRoute);
    _notify();
  }
}
