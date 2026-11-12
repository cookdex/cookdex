import 'app_navigation.dart';
import 'backup_feedback.dart';
import 'design_lab.dart';
import 'facelift_motion.dart';
import 'pixel_scroll.dart';
import 'retained_screen.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
import 'library_screen.dart';
import 'tag_addition.dart';
import 'library_recipe_page.dart';
import 'snapshots_screen.dart' as snapshots;
import 'how_cookdex_works_screen.dart';
import '../sync_presentation.dart';
import 'sync_screen.dart';
import 'smart_settings_screen.dart';
import '../smart_create_controller.dart';
import 'smart_create_screen.dart';
import 'smart_create_review.dart';
import 'create_settings_screen.dart';
import '../update_checker.dart';
import 'update_controls.dart';

class CookdexApp extends StatefulWidget {
  const CookdexApp({
    super.key,
    required this.store,
    required this.platform,
    this.drafts,
    this.importDrafts,
    this.createDiagnostics,
    this.importService,
    this.exportService,
    this.updates,
  });
  final RecipeStore store;
  final AppPlatform platform;
  final DraftStorage? drafts;
  final DraftStorage? importDrafts;
  final DraftStorage? createDiagnostics;
  final ImportService? importService;
  final ExportService? exportService;
  final UpdateController? updates;

  @override
  State<CookdexApp> createState() => _CookdexAppState();
}

class _CookdexAppState extends State<CookdexApp> with WidgetsBindingObserver {
  final _motion = isDevelopment ? MotionSettings() : null;
  final _navigator = GlobalKey<NavigatorState>();
  final _recipesNavigator = GlobalKey<NavigatorState>();
  final _recipesScreen = GlobalKey<RecipesScreenState>();
  late final ExportService _exports = widget.exportService ?? ExportService();
  final _settingsPlatform = SettingsPlatform();
  late final _installedVersion = _settingsPlatform.appVersion();
  late final _updates =
      widget.updates ??
      UpdateController(
        preferences: widget.store.preferences,
        installedVersion: () => _installedVersion,
      );
  late final SyncController? _sync = syncForStore(
    widget.store,
    widget.platform.isAndroid,
    _settingsPlatform.requestLocalNetwork,
    _settingsPlatform.hasLocalNetwork,
  );
  late final ImportService _smart =
      widget.importService ??
      NativeImportService(
        preferences: widget.store.preferences,
        existingTags: () =>
            widget.store.summaries.expand((r) => r.tags).toSet().toList(),
      );
  SmartCreateController? _createSession;
  SmartCreateController get _create => _createSession ??= SmartCreateController(
    platform: _smart.platform,
    local: widget.store.preferences,
    diagnostics: widget.createDiagnostics,
    existingTags: () => widget.store.summaries.expand((r) => r.tags).toSet(),
  );
  CoreSession? get _session => widget.store.repository is RustRecipeRepository
      ? (widget.store.repository as RustRecipeRepository).session
      : null;
  late final ScrollController _recipesScroll;
  final _shoppingScroll = PixelScrollController();
  final _settingsScroll = PixelScrollController();
  late final CookController _cook;
  late final _OverlayObserver _observer;
  final _activeTab = ValueNotifier<int>(0);
  int get _tab => _activeTab.value;
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

  Future<void> _openGitHub(BuildContext context) async {
    try {
      await widget.platform.openSource(cookdexGitHubUrl);
    } catch (_) {
      if (context.mounted) {
        showFeedback(
          context,
          'Could not open GitHub. Please try again.',
          kind: FeedbackKind.error,
        );
      }
    }
  }

  Future<void> _shareCookdex(BuildContext context) async {
    try {
      final outcome = await _exports.shareApp(
        isAndroid: widget.platform.isAndroid,
      );
      if (context.mounted && outcome == ExportOutcome.copied) {
        showFeedback(context, 'Link copied');
      }
    } catch (_) {
      if (context.mounted) {
        showFeedback(
          context,
          'Could not share cookdex. Please try again.',
          kind: FeedbackKind.error,
        );
      }
    }
  }

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
  final _cookInset = ValueNotifier<double?>(null);
  final _themeCache = <(ColorScheme, bool), ThemeData>{};

  ThemeData _theme(ColorScheme colors, {bool wide = false}) {
    final key = (colors, wide);
    final cached = _themeCache[key];
    if (cached != null) return cached;
    if (_themeCache.length >= 6) _themeCache.remove(_themeCache.keys.first);
    return _themeCache[key] = cookdexTheme(colors: colors, largerBody: wide);
  }

  void _updateCookInset() {
    _cookInset.value = _tab == 0 && _selected != null && _cook.active
        ? _cookFooterHeight
        : null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updates.afterFirstFrame();
    });
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
    _cook.addListener(_updateCookInset);
    _activeTab.addListener(_updateCookInset);
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
    _updates.setActive(_resumed);
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

  Widget _libraryRecipe(
    BuildContext recipeContext,
    String id, {
    required bool fromIdeas,
  }) => LibraryRecipePage(
    store: widget.store,
    recipeId: id,
    backTooltip: fromIdeas ? 'Back to ideas' : 'Back to Library',
    onDestinationSelected: fromIdeas ? _leaveIdeasForTab : null,
    platform: widget.platform,
    onActions: (scale) {
      final recipe = widget.store.summaries
          .where((r) => r.id == id)
          .firstOrNull;
      if (recipe != null) {
        _recipeActions(
          recipeContext,
          recipe,
          shoppingScale: scale,
          onDeleted: fromIdeas
              ? () {
                  if (recipeContext.mounted &&
                      ModalRoute.of(recipeContext)?.isCurrent == true) {
                    Navigator.of(recipeContext).pop();
                  }
                }
              : null,
          onSelect: () {
            Navigator.of(
              recipeContext,
              rootNavigator: true,
            ).popUntil((route) => route.isFirst);
            _recipeAction(recipeContext, id, 'select');
          },
        );
      }
    },
    onEdit: () => _openEditor(recipeContext, recipeId: id),
    onAddToShopping: (scale) =>
        _recipeAction(recipeContext, id, 'shopping', shoppingScale: scale),
  );

  Future<void> _pushRecipe(
    BuildContext context,
    String id, {
    bool fromIdeas = false,
  }) async {
    if (fromIdeas && !widget.store.summaries.any((recipe) => recipe.id == id)) {
      _createSession?.forgetSavedRecipe(id);
      return;
    }
    await Navigator.of(context).push<void>(
      cookdexRoute<void>(
        context,
        builder: (ctx) => _libraryRecipe(ctx, id, fromIdeas: fromIdeas),
      ),
    );
  }

  PageRoute<void> _savedRecipeRoute(
    BuildContext context,
    Recipe recipe,
    double sheetProgress,
  ) {
    return savedSmartCreateRecipeRoute(
      context,
      builder: (ctx) => _libraryRecipe(ctx, recipe.id, fromIdeas: true),
      recipe: recipe,
      sheetProgress: sheetProgress,
    );
  }

  void _leaveIdeasForTab(int index) {
    // Reveal the retained Recipes list at its current position. Only a
    // subsequent tap on that list is a request to scroll to the top.
    _navigator.currentState!.popUntil((route) => route.isFirst);
    if (_selected != null) _closeRecipe();
    if (index != 0 || _tab != 0) _selectTab(index);
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
    final resetGesture = _gestureTab != null || _tabBackProgress != null;
    _gestureTab = null;
    _tabBackProgress = null;
    FocusManager.instance.primaryFocus?.unfocus();
    if (index == 2 && _settingsScroll.hasClients) {
      _settingsScroll.jumpTo(0);
    } else if (index == 1 && _tab == 1 && _shoppingScroll.hasClients) {
      _shoppingScroll.jumpTo(0);
    } else if (index == 0 && _tab == 0) {
      if (_selected != null) {
        _closeRecipe();
      } else {
        _recipesScreen.currentState?.scrollToTop();
      }
    }
    _activeTab.value = index;
    if (resetGesture) setState(() {});
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
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      child: const AddRecipeChoices(),
    );
    if (choice != null && context.mounted) {
      if (choice == 'Recipe editing') {
        await _openEditor(context);
      } else if (choice == 'Smart Create') {
        await _openCreate(context);
      } else {
        await _openImport(context);
      }
    }
  }

  Future<Recipe?> _openEditor(
    BuildContext context, {
    String? recipeId,
    Candidate? imported,
    String importSourceLine = '',
    bool exactTextImport = false,
    bool smartCreated = false,
    String? createWarning,
    ValueChanged<Recipe>? markCreated,
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
        importSourceLine: importSourceLine,
        exactTextImport: exactTextImport,
        smartCreated: smartCreated,
        createWarning: createWarning,
      );
      if (!context.mounted) return null;
      Widget buildEditor(ValueChanged<Recipe>? onSaved) => RecipeEditor(
        controller: controller!,
        onSmartCreateSaved: onSaved,
        tagSuggestions: widget.store.summaries
            .expand((r) => r.tags)
            .toSet()
            .toList(),
        ingredientSuggestions: widget.store.summaries
            .expand((r) => r.ingredients)
            .toSet()
            .toList(),
      );
      final editorRoute = smartCreated && recovered == null
          ? smartCreateReviewRoute(
              context,
              buildEditor: buildEditor,
              onLeave: (recipe) => markCreated?.call(recipe),
              buildRecipeRoute: _savedRecipeRoute,
            )
          : cookdexRoute<Recipe>(context, builder: (_) => buildEditor(null));
      final saved = await Navigator.of(
        context,
        rootNavigator: true,
      ).push<Recipe>(editorRoute);
      if (smartCreated) {
        await editorRoute.completed;
      }
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

  Future<void> _createSettings(BuildContext context) => openCreateSettings(
    context,
    preferences: widget.store.preferences,
    service: _smart,
    lastDiagnostic: _create.lastDiagnostic,
    clearDiagnostic: _create.clearDiagnostic,
  );

  Future<void> _openKey(BuildContext context) => openGeminiKey(
    context,
    service: _smart,
    openUrl: widget.platform.openSource,
  );

  Future<void> _openCreate(BuildContext context) async {
    if (_importOpen) return;
    _importOpen = true;
    try {
      await Navigator.of(context, rootNavigator: true).push<void>(
        cookdexRoute<void>(
          context,
          builder: (routeContext) => SmartCreateScreen(
            controller: _create,
            onKey: _openKey,
            onSettings: _createSettings,
            onStaples: (c) =>
                openCreateStaples(c, preferences: widget.store.preferences),
            onViewRecipe: (id) =>
                _pushRecipe(routeContext, id, fromIdeas: true),
            onReview: (c, candidate) async {
              final idea = _create.reviewIdeaTitle;
              await _openEditor(
                c,
                imported: candidate,
                smartCreated: true,
                createWarning: _create.recipeWarning,
                markCreated: (recipe) {
                  if (idea != null) _create.markSaved(idea, recipe.id);
                },
              );
            },
            onShop: (names) => widget.store.editShopping(
              ShoppingEdit.addManualItems(names: names),
            ),
          ),
        ),
      );
    } finally {
      _importOpen = false;
      _drainShares();
    }
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
            preferences: widget.store.preferences,
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
                openUrl: widget.platform.openSource,
                initialInput: incoming == null
                    ? null
                    : (c) => incoming.apply(c),
                onReview: (context, candidate) => _openEditor(
                  context,
                  imported: candidate,
                  importSourceLine: controller.reviewSourceLine,
                ),
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

  Future<void> _deleteSelection(BuildContext context) async {
    if (_selectionBusy || _selection?.isNotEmpty != true) return;
    final ids = _selection!.toList(growable: false);
    final generation = widget.store.generation;
    setState(() => _selectionBusy = true);
    try {
      if (!await confirmCookdex(
            context,
            title:
                'Delete ${ids.length} ${ids.length == 1 ? 'recipe' : 'recipes'}?',
            action: 'Delete',
            destructive: true,
            content: const Text(
              'A snapshot will be saved first. Deletions also reach your synced devices.',
            ),
          ) ||
          !context.mounted) {
        return;
      }
      final navigator = Navigator.of(context, rootNavigator: true);
      final progress = DialogRoute<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text('Deleting recipes'),
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 24),
                Expanded(child: Text('Saving a snapshot and deleting…')),
              ],
            ),
          ),
        ),
      );
      unawaited(navigator.push(progress));
      try {
        await widget.store.deleteRecipes(generation, ids);
      } finally {
        if (progress.isActive) navigator.removeRoute(progress);
      }
      if (mounted) setState(() => _selection = null);
      if (context.mounted) {
        showFeedback(
          context,
          'Deleted ${ids.length} ${ids.length == 1 ? 'recipe' : 'recipes'}',
        );
      }
    } catch (_) {
      if (context.mounted) {
        showFeedback(
          context,
          'Could not delete recipes. Nothing was deleted. Please try again.',
          kind: FeedbackKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _selectionBusy = false);
    }
  }

  Future<void> _tagSelection(BuildContext context) async {
    if (_selectionBusy || _selection?.isNotEmpty != true) return;
    final ids = Set<String>.of(_selection!);
    setState(() => _selectionBusy = true);
    try {
      final result = await addTagToRecipes(
        context,
        widget.store,
        recipeIds: ids,
      );
      if (mounted && result != null) setState(() => _selection = null);
    } finally {
      if (mounted) setState(() => _selectionBusy = false);
    }
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

  Future<void> _recipeActions(
    BuildContext context,
    RecipeSummary recipe, {
    int? shoppingScale,
    VoidCallback? onSelect,
    VoidCallback? onDeleted,
  }) => showRecipeActions(
    context: context,
    store: widget.store,
    recipe: recipe,
    onDeleted: () {
      if (!mounted) return;
      _createSession?.forgetSavedRecipe(recipe.id);
      if (_selected == recipe.id) _closeRecipe();
      onDeleted?.call();
    },
    onEdit: () => _openEditor(context, recipeId: recipe.id),
    onAction: (action) async {
      if (action == 'select' && onSelect != null) {
        onSelect();
      } else {
        await _recipeAction(
          context,
          recipe.id,
          action,
          shoppingScale: shoppingScale,
        );
      }
    },
  );

  Future<void> _recipeAction(
    BuildContext context,
    String id,
    String action, {
    int? shoppingScale,
  }) async {
    if (action == 'select') {
      _closeRecipe();
      setState(() {
        _activeTab.value = 0;
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
          scale: shoppingScale ?? (_selected == id ? _cook.scale : 2),
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
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Recipes restored'),
          content: Text(
            '${restored.added} added · ${restored.updated} updated · ${restored.skipped} skipped'
            '${restored.conflicts.isEmpty ? '' : '\n${restored.conflicts.length} ${restored.conflicts.length == 1 ? 'conflict' : 'conflicts'} kept unchanged.'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      );
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
    _cook.removeListener(_updateCookInset);
    _activeTab.removeListener(_updateCookInset);
    _cookInset.dispose();
    _activeTab.dispose();
    _motion?.dispose();
    _updates.dispose();
    _incoming.dispose();
    _snapshotTimer?.cancel();
    _sync?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    widget.store.preferences.removeListener(_preferencesChanged);
    _recipesScroll.dispose();
    _shoppingScroll.dispose();
    _settingsScroll.dispose();
    _cook.dispose();
    _createSession?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => isDevelopment
      ? FaceliftMotion(settings: _motion!, child: _app())
      : _app();

  Widget _app() => MaterialApp(
    scrollBehavior: const CookdexScrollBehavior(),
    title: appName,
    debugShowCheckedModeBanner: false,
    navigatorKey: _navigator,
    navigatorObservers: [_observer],
    themeMode: widget.store.preferences.themeMode,
    theme: _theme(
      widget.platform.isAndroid && widget.store.preferences.wallpaperColors
          ? _lightWallpaper ?? cookdexLightColors
          : cookdexLightColors,
    ),
    darkTheme: _theme(
      widget.platform.isAndroid && widget.store.preferences.wallpaperColors
          ? _wallpaper ?? cookdexColors
          : cookdexColors,
    ),
    themeAnimationDuration:
        WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .disableAnimations
        ? Duration.zero
        : FaceliftMotion.themeFade,
    builder: (context, child) => Theme(
      data: _theme(
        Theme.of(context).colorScheme,
        wide: WindowSizeClass.of(context) != WindowSizeClass.compact,
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
    home: RetainedScreen(
      child: Builder(
        builder: (context) {
          final pages = _buildTabPages(context);
          return ValueListenableBuilder<int>(
            valueListenable: _activeTab,
            builder: (context, index, _) => PopScope(
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
                    // Scaffold positions floating snackbars above this slot.
                    // Reserving the pill's height here avoids broadcasting a
                    // new Theme to every retained page on cook entry and exit.
                    floatingActionButton: ValueListenableBuilder<double?>(
                      valueListenable: _cookInset,
                      builder: (_, height, _) =>
                          SizedBox(width: 0, height: height ?? 0),
                    ),
                    body: Row(
                      children: [
                        if (WindowSizeClass.of(context) !=
                            WindowSizeClass.compact)
                          AppNavigation(
                            store: widget.store,
                            selected: _tab,
                            onSelect: _selectTab,
                            rail: true,
                          ),
                        Expanded(
                          child: RetainedTabTransition(
                            index: _tab,
                            readyToWarm: !widget.store.loading,
                            backProgress: _tabBackProgress,
                            backFromRight: _backFromRight,
                            children: pages,
                          ),
                        ),
                      ],
                    ),
                    bottomNavigationBar: ListenableBuilder(
                      listenable: Listenable.merge([_cook, widget.store]),
                      builder: (context, _) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_tab == 0 &&
                              _selected == null &&
                              _selection == null &&
                              !_obscured &&
                              !_keyboardVisible)
                            UpdateNotice(
                              controller: _updates,
                              openPage: widget.platform.openSource,
                            ),
                          if (WindowSizeClass.of(context) ==
                                  WindowSizeClass.compact &&
                              MediaQuery.viewInsetsOf(context).bottom == 0)
                            AppNavigation(
                              store: widget.store,
                              selected: _tab,
                              onSelect: _selectTab,
                              cooking: _tab == 0 && _selected != null && _cook.active,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );

  List<Widget> _buildTabPages(BuildContext context) => [
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
              key: _recipesScreen,
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
                  : () => setState(() => _selection = null),
              onSelectAll: _selectionBusy
                  ? null
                  : () => setState(
                      () => _selection = widget.store.visibleRecipes
                          .map((r) => r.id)
                          .toSet(),
                    ),
              onShareSelection: _selectionBusy
                  ? null
                  : () => _selectionAction(context),
              onShoppingSelection: _selectionBusy
                  ? null
                  : () => _selectionAction(context, shopping: true),
              onTagSelection: _selectionBusy
                  ? null
                  : () => _tagSelection(context),
              onDeleteSelection: _selectionBusy
                  ? null
                  : () => _deleteSelection(context),
              store: widget.store,
              preferences: widget.store.preferences,
              controller: _recipesScroll,
              onOpenRecipe: _openRecipe,
              onAdd: () => _add(context),
              keyboardVisible: _keyboardVisible,
              onDesignLab: isDevelopment ? () => showDesignLab(context) : null,
              onWrite: () => _openEditor(context),
              onImport: () => _openImport(context),
              onCreate: () => _openCreate(context),
              onSync: () => _manualSync(context),
              syncController: _sync,
              onSyncStatus: () => _openSyncIndicator(context),
              onHelp: () => _openHelp(context),
              onRestore: () => _restore(context),
              onActions: (recipe) => _recipeActions(context, recipe),
            ),
          ),
        ),
        if (_selected != null)
          OpaqueMaterialPage<void>(
            key: ValueKey(_selected),
            recipeOpening: true,
            name: _selected,
            child: _RecipeBackScope(
              tab: _activeTab,
              child: SafeArea(
                bottom: false,
                child: RecipeTextScale(
                  factor: widget.store.preferences.recipeTextSize.factor,
                  child: RecipeDetail(
                    key: ValueKey(_selected),
                    store: widget.store,
                    recipeId: _selected!,
                    cook: _cook,
                    onControlsHeight: (height) {
                      if (mounted && _cookFooterHeight != height) {
                        _cookFooterHeight = height;
                        _updateCookInset();
                      }
                    },
                    showControls: true,
                    systemBottomInset: MediaQuery.viewPaddingOf(context).bottom,
                    onBack: () => _recipesNavigator.currentState?.maybePop(),
                    onActions: () {
                      final recipe = widget.store.summaries
                          .where((r) => r.id == _selected)
                          .firstOrNull;
                      if (recipe != null) {
                        _recipeActions(context, recipe);
                      }
                    },
                    onEdit: () => _openEditor(context, recipeId: _selected),
                    onSource: widget.platform.openSource,
                    onAddToShopping: () =>
                        _recipeAction(context, _selected!, 'shopping'),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
    ShoppingScreen(
      controller: _shoppingScroll,
      store: widget.store,
      onSaveText: (shoppingContext) => _export(
        shoppingContext,
        () => _exports.shopping(widget.store.shopping, widget.store.summaries),
      ),
    ),
    SettingsScreen(
      controller: _settingsScroll,
      onLibrary: () => Navigator.of(context, rootNavigator: true).push<void>(
        cookdexRoute<void>(
          context,
          builder: (_) => LibraryScreen(
            store: widget.store,
            onOpenRecipe: (libraryContext, id) =>
                _pushRecipe(libraryContext, id),
          ),
        ),
      ),
      onGitHub: () => _openGitHub(context),
      onShareCookdex: () => _shareCookdex(context),
      readHasPrevious: () => widget.store.hasPrevious,
      recoveryChanges: widget.store,
      busy: _restoring,
      syncSummary:
          '${_sync?.summary ?? 'Off'}${widget.store.conflicts.isEmpty ? '' : ' · ${widget.store.conflicts.length} conflicts'}',
      syncChanges: _sync,
      readSyncSummary: () =>
          '${_sync?.summary ?? 'Off'}${widget.store.conflicts.isEmpty ? '' : ' · ${widget.store.conflicts.length} conflicts'}',
      onSync: _sync == null ? null : () => _openSync(context),
      onDownloadRecipeZip: _session == null ? null : () => _backup(context),
      onRestoreRecipeZip: () => _restore(context),
      onSnapshots: _session == null ? null : () => _openSnapshots(context),
      snapshotsFailing: _snapshotsFailing,
      onRecoverPreviousSave: _session == null ? null : () => _recover(context),
      onSaveReadableCookbook: () => _saveCookbook(context),
      onSmartImportSettings: () => openSmartSettings(
        context,
        service: _smart,
        preferences: widget.store.preferences,
        openUrl: widget.platform.openSource,
      ),
      onGeminiKey: () => _openKey(context),
      onSmartCreateSettings: () => _createSettings(context),
      shoppingKeepAwake: widget.store.preferences.shoppingKeepAwake,
      onShoppingKeepAwake: widget.store.preferences.setShoppingKeepAwake,
      recipeTextScale: widget.store.preferences.recipeTextSize.factor,
      onRecipeTextScale: (factor) => widget.store.preferences.setRecipeTextSize(
        RecipeTextSize.values.firstWhere((s) => s.factor == factor),
      ),
      isAndroid: widget.platform.isAndroid,
      themeMode: widget.store.preferences.themeMode,
      onThemeMode: widget.store.preferences.setThemeMode,
      wallpaperColors: widget.store.preferences.wallpaperColors,
      onWallpaperColors: widget.store.preferences.setWallpaperColors,
      version: 'Version unavailable',
      installedVersion: _installedVersion,
      updateSettings: UpdateSettingsPanel(
        controller: _updates,
        openPage: widget.platform.openSource,
      ),
      onHowCookdexWorks: () => _openHelp(context),
    ),
  ];
}

class _RecipeBackScope extends StatelessWidget {
  const _RecipeBackScope({required this.tab, required this.child});
  final ValueNotifier<int> tab;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: tab,
    child: child,
    builder: (context, index, child) =>
        PopScope(canPop: index == 0, child: child!),
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
