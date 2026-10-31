import 'dart:math' as math;
import 'dart:collection';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/rendering.dart';

import '../src/rust/api.dart';
import '../tag_labels.dart';
import '../yield_presentation.dart';
import 'prepared_card_title.dart';

class CardGeometry {
  CardGeometry({
    required this.height,
    required this.titleHeight,
    required this.descriptionHeight,
    required this.metadataHeight,
    required this.tagsHeight,
  });
  PreparedTitle? title;
  List<String>? tagLabels;
  int? visibleTags;
  double? tagWidth;
  final double height,
      titleHeight,
      descriptionHeight,
      metadataHeight,
      tagsHeight;
}

/// Numeric geometry survives disposal. Reversal windows share a bounded cache.
/// Uses the same native paragraph styles/constraints as the finished card.
class CardGeometryCache {
  // Native Text applies these accessibility settings beyond the resolved theme.
  // Keep its complete layout when the prepared path cannot reproduce them.
  static bool supports(BuildContext context) =>
      !MediaQuery.boldTextOf(context) &&
      MediaQuery.maybeLineHeightScaleFactorOverrideOf(context) == null &&
      MediaQuery.maybeLetterSpacingOverrideOf(context) == null &&
      MediaQuery.maybeWordSpacingOverrideOf(context) == null;

  bool supported = true;
  // Two opposite 48-title preparation windows plus up to 32 retained cards.
  // A reversal must not evict the other direction while warming this one.
  static const titleCapacity = 128;
  bool lastHit = false;
  final _text = <Object, Size>{};
  final _cards = HashMap<RecipeSummary, CardGeometry>.identity();
  final _titles = <CardGeometry>[];
  Object? _environment;
  TextStyle? _title, _body, _tag;
  late TextScaler _scaler;
  late TextDirection _direction;
  Locale? _locale;
  TextHeightBehavior? _behavior;
  double _width = 0;
  bool _grid = false;
  double? _fixedHeight;
  Iterator<CardGeometry?>? _job;
  RecipeSummary? _jobRecipe;
  int _fontEpoch = -1;

  void clear() {
    for (final card in _titles) {
      card.title?.releaseCache();
      card.title = null;
    }
    _titles.clear();
    _text.clear();
    _cards.clear();
    _job = null;
    _jobRecipe = null;
  }

  void configure(
    BuildContext context,
    double width, {
    bool grid = false,
    double? fixedHeight,
  }) {
    final theme = Theme.of(context).textTheme;
    final defaults = DefaultTextStyle.of(context);
    final canPrepare = supports(context);
    final environment = (
      canPrepare,
      width,
      grid,
      fixedHeight,
      theme,
      defaults.style,
      MediaQuery.textScalerOf(context),
      Directionality.of(context),
      Localizations.maybeLocaleOf(context),
      DefaultTextHeightBehavior.maybeOf(context),
      _Fonts.epoch,
    );
    if (_environment == environment) return;
    clear();
    _environment = environment;
    supported = canPrepare;
    _fontEpoch = _Fonts.epoch;
    _width = width;
    _grid = grid;
    _fixedHeight = fixedHeight;
    _title = defaults.style.merge(
      theme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
    _body = theme.bodySmall;
    _tag = theme.labelSmall;
    _scaler = MediaQuery.textScalerOf(context);
    _direction = Directionality.of(context);
    _locale = Localizations.maybeLocaleOf(context);
    _behavior = DefaultTextHeightBehavior.maybeOf(context);
  }

  bool contains(RecipeSummary recipe) => _cards.containsKey(recipe);
  bool needsPreparation(RecipeSummary recipe) =>
      supported && _cards[recipe]?.title == null;

  PreparedTitle _prepareTitle(RecipeSummary recipe) => PreparedTitle(
    TextPainter(
      text: TextSpan(text: recipe.title, style: _title),
      textDirection: _direction,
      textScaler: _scaler,
      maxLines: _grid ? 2 : 3,
      ellipsis: '…',
      locale: _locale,
      textHeightBehavior: _behavior,
    )..layout(maxWidth: _width - 72),
    maxWidth: _width - 72,
  );

  void _retainTitle(CardGeometry value) {
    _titles.add(value);
    if (_titles.length > titleCapacity) {
      final old = _titles.removeAt(0);
      old.title?.releaseCache();
      old.title = null;
    }
  }

  CardGeometry? measure(
    BuildContext context,
    RecipeSummary recipe,
    double width, {
    bool grid = false,
    double? fixedHeight,
  }) {
    configure(context, width, grid: grid, fixedHeight: fixedHeight);
    return measurePrepared(recipe);
  }

  CardGeometry? measurePrepared(RecipeSummary recipe) {
    lastHit = false;
    if (!supported ||
        _fontEpoch != _Fonts.epoch ||
        !_width.isFinite ||
        _width <= 72 ||
        (_grid && _fixedHeight == null)) {
      return null;
    }
    if (_cards[recipe] case final value?) {
      lastHit = true;
      return value;
    }
    final job = identical(_jobRecipe, recipe)
        ? _job!
        : _calculate(recipe).iterator;
    while (job.moveNext()) {}
    if (identical(_jobRecipe, recipe)) {
      _job = null;
      _jobRecipe = null;
    }
    return _cards[recipe];
  }

  /// A lookup only: a Top landing must not drain unprepared paragraph work.
  CardGeometry? prepared(RecipeSummary recipe) {
    if (!supported) return null;
    final value = _cards[recipe];
    return value?.title == null ? null : value;
  }

  /// One native paragraph per step; synchronous misses drain the same job.
  bool prepareStep(RecipeSummary recipe) {
    if (!supported) return true;
    if (_cards[recipe] case final value?) {
      if (value.title == null) {
        value.title = _prepareTitle(recipe);
        _retainTitle(value);
      }
      return true;
    }
    if (!identical(_jobRecipe, recipe)) {
      _jobRecipe = recipe;
      _job = _calculate(recipe).iterator;
    }
    if (!_job!.moveNext()) {
      _job = null;
      _jobRecipe = null;
      return true;
    }
    return _cards.containsKey(recipe);
  }

  Iterable<CardGeometry?> _calculate(RecipeSummary recipe) sync* {
    final width = _width, grid = _grid, fixedHeight = _fixedHeight;
    final body = _body, tag = _tag;
    final scaler = _scaler,
        direction = _direction,
        locale = _locale,
        behavior = _behavior;
    final tags = normalizeTags(recipe.tags);
    Size text(
      String value,
      TextStyle? style,
      double maxWidth, {
      int? lines,
      bool ellipsis = false,
    }) {
      final textKey = (
        value,
        style,
        maxWidth,
        lines,
        ellipsis,
        scaler,
        direction,
        locale,
        behavior,
      );
      if (_text[textKey] case final size?) return size;
      final painter = TextPainter(
        text: TextSpan(text: value, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: lines,
        ellipsis: ellipsis ? '…' : null,
        locale: locale,
        textHeightBehavior: behavior,
      )..layout(maxWidth: maxWidth);
      final size = painter.size;
      painter.dispose();
      if (_text.length >= 4096) _text.remove(_text.keys.first);
      return _text[textKey] = size;
    }

    // Both layouts reserve 72dp beside the text: card padding and star slot.
    final contentWidth = width - 72;
    final preparedTitle = _prepareTitle(recipe);
    final titlePainter = preparedTitle.painter;
    final holder = CardGeometry(
      height: 0,
      titleHeight: 0,
      descriptionHeight: 0,
      metadataHeight: 0,
      tagsHeight: 0,
    )..title = preparedTitle;
    _retainTitle(holder);
    final titleHeight = titlePainter.height;
    yield null;
    final descriptionHeight = recipe.description.isEmpty
        ? 0.0
        : text(
            recipe.description,
            body,
            contentWidth,
            lines: 2,
            ellipsis: true,
          ).height;
    yield null;
    var metadataHeight = 0.0;
    var lineWidth = 0.0;
    var lineHeight = 0.0;
    final yieldText = presentRecipeYield(recipe.servings).text;
    final metadata = <String>[
      if (yieldText.isNotEmpty) yieldText,
      if (recipe.totalTime.isEmpty) ...[
        if (recipe.prepTime.isNotEmpty) 'Prep ${recipe.prepTime}',
        if (recipe.cookTime.isNotEmpty) 'Cook ${recipe.cookTime}',
      ],
      if (recipe.totalTime.isNotEmpty) recipe.totalTime,
    ];
    for (final value in metadata) {
      final size = text(value, body, contentWidth - 20);
      yield null;
      final itemWidth = size.width + 20;
      if (lineWidth > 0 && lineWidth + 14 + itemWidth > contentWidth) {
        metadataHeight += lineHeight + 4;
        lineWidth = 0;
        lineHeight = 0;
      }
      lineWidth += (lineWidth > 0 ? 14 : 0) + itemWidth;
      lineHeight = math.max(lineHeight, math.max(15, size.height));
    }
    metadataHeight += lineHeight;
    var tagsHeight = 0.0;
    var visible = tags.length;
    if (tags.isNotEmpty) {
      final sizes = <Size>[];
      for (final value in tags) {
        sizes.add(text(value, tag, double.infinity));
        yield null;
      }

      while (visible > 0) {
        final hidden = tags.length - visible;
        final occupied =
            sizes
                .take(visible)
                .fold(0.0, (sum, size) => sum + size.width + 16) +
            (hidden > 0
                ? text('+$hidden', tag, double.infinity).width + 16
                : 0) +
            6 * (visible + (hidden > 0 ? 1 : 0) - 1);
        yield null;
        if (occupied <= contentWidth) break;
        visible--;
      }
      for (final size in sizes.take(visible)) {
        tagsHeight = math.max(tagsHeight, size.height + 8);
      }
      if (visible < tags.length) {
        final occupied =
            sizes
                .take(visible)
                .fold(0.0, (sum, size) => sum + size.width + 16) +
            6 * visible;
        tagsHeight = math.max(
          tagsHeight,
          text(
                '+${tags.length - visible}',
                tag,
                math.max(0, contentWidth - occupied - 16),
              ).height +
              8,
        );
      }
    }
    final footer =
        metadataHeight +
        tagsHeight +
        (metadataHeight > 0 && tagsHeight > 0 ? 8 : 0);
    final bodyHeight =
        titleHeight +
        (descriptionHeight > 0 ? 4 + descriptionHeight : 0) +
        (footer > 0 ? 8 + footer : 0);
    final value = CardGeometry(
      height: grid ? fixedHeight! : 20 + math.max(48, bodyHeight),
      titleHeight: titleHeight,
      descriptionHeight: descriptionHeight,
      metadataHeight: metadataHeight,
      tagsHeight: tagsHeight,
    );
    value.title = holder.title;
    value.tagLabels = tags;
    value.visibleTags = visible;
    value.tagWidth = contentWidth;
    final slot = _titles.indexOf(holder);
    if (slot >= 0) _titles[slot] = value;
    if (_cards.length >= 4096) _cards.remove(_cards.keys.first);
    _cards[recipe] = value;
    yield value;
  }
}

class _Fonts {
  static int get epoch {
    _listen;
    return _epoch;
  }

  static int _epoch = 0;
  static final bool _listen = (() {
    PaintingBinding.instance.systemFonts.addListener(() => _epoch++);
    return true;
  })();
}

/// Work belongs to mounted cards; only numeric geometry survives their disposal.
class CardPreparation {
  static final _lists = <CardPreparation>{};
  static bool _watching = false;
  static void _watch(CardPreparation work) {
    _lists.add(work);
    if (_watching) return;
    _watching = true;
    // One global observer, with explicit registration, never retains disposed
    // screen States through SchedulerBinding's non-removable callback list.
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      if (_lists.isEmpty) return;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        for (final work in _lists) {
          work._queue(afterLayout: true);
        }
      });
    });
  }

  final geometry = CardGeometryCache();
  final paused = ValueNotifier(false);
  final _pending = <_ProgressiveCardState>{};
  final _built = <_ProgressiveCardState>{};
  List<RecipeSummary> _recipes = const [];
  final _indices = HashMap<RecipeSummary, int>.identity();
  bool _configured = false;
  int _columns = 1, _topPrepareAt = 0, _topPrepareEnd = 0;
  double _aheadStepUs = 700;
  void configure(
    BuildContext context,
    List<RecipeSummary> recipes,
    double width, {
    bool grid = false,
    double? fixedHeight,
    int columns = 1,
  }) {
    _columns = columns;
    geometry.configure(context, width, grid: grid, fixedHeight: fixedHeight);
    _configured = true;
    if (!identical(recipes, _recipes)) {
      _topPrepareAt = _topPrepareEnd = 0;
      _recipes = recipes;
      _indices.clear();
      for (var i = 0; i < recipes.length; i++) {
        _indices[recipes[i]] = i;
      }
    }
  }

  /// Top-return work uses the existing paragraph budget only during the rush.
  void prepareTopReturn(double extent) {
    _topPrepareAt = 0;
    _topPrepareEnd = math.min(_recipes.length, (extent / 68).ceil() * _columns);
    _queue();
  }

  void finishTopReturn() {
    jumping = false;
    _topPrepareAt = _topPrepareEnd = 0;
  }

  // A scan is resumed across callbacks. Ancestors are resolved once per mounted
  // card; no paragraph step scans the mounted set or recomputes the viewport.
  List<_ProgressiveCardState> _scan = const [];
  int _scanAt = 0, _scanLow = 0, _scanHigh = -1;
  int _low = 0, _high = -1, _aheadCursor = 0, _rankCursor = 0;
  bool _aheadDirty = true;
  int _scanMotion = -1, _motionRevision = 0;

  bool _room(int deadline, [int reserve = 80]) =>
      dev.Timeline.now + reserve < deadline;

  void _discoverWindow(int deadline) {
    if (!_room(deadline)) return;
    if (_scan.isEmpty) {
      _scan = _built.toList(growable: false);
      _scanAt = 0;
      _scanLow = _recipes.length;
      _scanHigh = -1;
      _scanMotion = _motionRevision;
    }
    var units = 0;
    while (_scanAt < _scan.length && units++ < 16 && _room(deadline)) {
      final card = _scan[_scanAt++];
      final index = _indices[card.widget.recipe];
      if (index != null && card._buildRect != null) {
        _scanLow = math.min(_scanLow, index);
        _scanHigh = math.max(_scanHigh, index);
        if (card._automatic && (card._stage ?? 4) < 4) _pending.add(card);
      }
    }
    if (_scanAt == _scan.length) {
      if (_low != _scanLow || _high != _scanHigh) {
        _aheadCursor = 0;
        _aheadDirty = true;
      }
      _low = _scanLow;
      _high = _scanHigh;
      if (_high < 0) _aheadDirty = false;
      _scan = const [];
    }
  }

  int _nextGeometry(int deadline) {
    if (!_configured ||
        accessible ||
        !_active ||
        _high < 0 ||
        (_contact && !_inMotion)) {
      return -1;
    }
    // Each direction uses at most 48 entries. Both windows and retained cards
    // fit in the title cache; reversing does not require rewarming their union.
    final capacity = math.max(0, 48 - (_high - _low + 1));
    final ahead = math.min(
      (viewport * 3 / 68).ceil(),
      (capacity * .75).floor(),
    );
    final behind = math.min((viewport / 68).ceil(), capacity - ahead);
    var start = math.max(0, _low - (direction >= 0 ? behind : ahead));
    var end = math.min(
      _recipes.length - 1,
      _high + (direction >= 0 ? ahead : behind),
    );
    // A partial scan may span disjoint mounted regions after reversing. Its
    // preparation range must still fit the paragraph cache, regardless of span.
    if (direction >= 0) {
      start = math.max(start, end - 47);
    } else {
      end = math.min(end, start + 47);
    }
    final length = end - start + 1;
    var scanned = 0;
    while (_aheadCursor < length && scanned++ < 12 && _room(deadline)) {
      final i = direction >= 0 ? start + _aheadCursor : end - _aheadCursor;
      if (geometry.needsPreparation(_recipes[i])) return i;
      _aheadCursor++;
    }
    if (_aheadCursor >= length) _aheadDirty = false;
    return -1;
  }

  void _prepareAhead(int deadline) {
    if (!geometry.supported ||
        accessible ||
        !_active ||
        (_contact && !_inMotion)) {
      return;
    }
    if (_inMotion && dev.Timeline.now < _recentLongUntilUs) return;
    var steps = 0;
    while (steps++ < 8 && _room(deadline, _aheadStepUs.ceil())) {
      final warmingTop = _topPrepareAt < _topPrepareEnd;
      final index = warmingTop ? _topPrepareAt : _nextGeometry(deadline);
      if (index < 0 || !_room(deadline, _aheadStepUs.ceil())) return;
      final stepStart = dev.Timeline.now;
      final ready = geometry.prepareStep(_recipes[index]);
      if (warmingTop && ready) _topPrepareAt++;
      final cost = dev.Timeline.now - stepStart;
      _aheadStepUs = math
          .max(_aheadStepUs * .9, cost.toDouble())
          .clamp(100, 1000);
    }
  }

  final _measured = <_ProgressiveCardState>{};
  BuildContext? _context;
  ScrollController? _controller;
  bool _visible = true, _contact = false, _moving = false;
  bool jumping = false;
  double speed = 0, direction = 1, viewport = 800;
  int? _callback;
  int _lastMotionUs = 0;
  bool _frameEndPending = false;
  bool _sleepingForTouch = false;
  int _recentLongUntilUs = 0, _previousStage = 0;
  final _stageCosts = <double>[0, 1800, 1800, 2600, 2300];
  double _baseCostUs = 1000;

  bool get fast => speed > viewport * 1.35;
  bool get accessible => SemanticsBinding.instance.semanticsEnabled;
  bool get _active => _visible && !paused.value;
  double get _budgetUs {
    final hz = _context == null ? 60.0 : View.of(_context!).display.refreshRate;
    return 1000000 / (hz > 0 ? hz : 60);
  }

  void pauseForNavigation() {
    paused.value = true;
  }

  bool get _inMotion => _controller?.hasClients == true
      ? _controller!.position.isScrollingNotifier.value
      : _moving;
  bool get _full =>
      !geometry.supported || accessible || jumping || (!_inMotion && !_contact);

  void _timings(List<FrameTiming> frames) {
    if (frames.isEmpty || !_inMotion) return;
    final latest = frames.last;
    if (math.max(
          latest.buildDuration.inMicroseconds,
          latest.rasterDuration.inMicroseconds,
        ) >
        _budgetUs) {
      _recentLongUntilUs = dev.Timeline.now + 20000;
    }
  }

  Rect get _window {
    final render = _context?.findRenderObject();
    return render is RenderBox && render.hasSize
        ? render.localToGlobal(Offset.zero) & render.size
        : Rect.fromLTWH(0, 0, 10000, viewport);
  }

  bool _eligible(Rect rect, Rect window) =>
      rect.overlaps(window) ||
      !_contact ||
      dev.Timeline.now - _lastMotionUs < 75000;

  void _queue({bool afterLayout = false}) {
    // Scheduling and wakeup checks are constant-time, including the global
    // post-layout observer. All discovery/ranking runs inside _runFrame's budget.
    if (!geometry.supported ||
        accessible ||
        (_sleepingForTouch && _contact && !_inMotion) ||
        _callback != null ||
        _frameEndPending ||
        !_active ||
        (_pending.isEmpty &&
            _topPrepareAt >= _topPrepareEnd &&
            !_aheadDirty &&
            _scan.isEmpty &&
            _scanMotion == _motionRevision)) {
      return;
    }
    _callback = SchedulerBinding.instance.scheduleFrameCallback((_) {
      _callback = null;
      if (!_active) return;
      final started = dev.Timeline.now;
      _frameEndPending = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _frameEndPending = false;
        if (!_active) return;
        final callbackStart = dev.Timeline.now;
        _runFrame(started, callbackStart);
      });
    });
  }

  void _runFrame(int frameStarted, int callbackStarted) {
    final elapsed = callbackStarted - frameStarted;
    final moving = _inMotion;
    final previousCost = _previousStage == 0
        ? 0.0
        : _stageCosts[_previousStage];
    if (_previousStage != 0) {
      // A pause is not a new permanent price for the stage. Clamp the sample
      // before smoothing so a single GC/preemption cannot make every future
      // reservation exceed the remaining budget and starve moving fill.
      final sample = math
          .max(500, elapsed - _baseCostUs)
          .clamp(500, _budgetUs * .5);
      _stageCosts[_previousStage] =
          _stageCosts[_previousStage] * .75 + sample * .25;
    } else {
      _baseCostUs = (_baseCostUs * .75 + elapsed * .25).clamp(
        500,
        _budgetUs * .8,
      );
    }
    _previousStage = 0;
    // All bookkeeping shares this deadline. Work resumes next frame, with an
    // extra 1.5ms ceiling even when a very cheap UI frame leaves more spare time.
    final deadline = math.min(
      frameStarted + (_budgetUs * .82).floor(),
      callbackStarted + 1500,
    );
    if (!_room(deadline)) {
      _queue();
      return;
    }
    final window = _window;
    if (_scan.isNotEmpty || _scanMotion != _motionRevision || _aheadDirty) {
      _discoverWindow(deadline);
    }
    _ProgressiveCardState? best;
    var bestPriority = double.infinity;
    final pending = _pending.toList(growable: false);
    var visited = 0;
    while (visited < pending.length && visited < 64 && _room(deadline)) {
      final state = pending[_rankCursor % pending.length];
      _rankCursor++;
      visited++;
      final rect = state._buildRect;
      if (rect == null) {
        _pending.remove(state);
        continue;
      }
      if (!_eligible(rect, window)) continue;
      final visible = rect.overlaps(window);
      final ahead = direction >= 0
          ? rect.top >= window.bottom
          : rect.bottom <= window.top;
      final distance = visible
          ? (rect.center.dy - window.center.dy).abs()
          : math.max(window.top - rect.bottom, rect.top - window.bottom);
      final priority = (visible ? 0 : (ahead ? 100000 : 200000)) + distance;
      if (priority < bestPriority) {
        best = state;
        bestPriority = priority;
      }
    }
    if (best != null && _room(deadline)) {
      final next = (best._stage ?? 0) + 1;
      final liveBase = math.max(_baseCostUs, elapsed - previousCost);
      final remaining =
          _budgetUs * .85 - liveBase - (dev.Timeline.now - callbackStarted);
      final visibleAtRest = !moving && bestPriority < 100000;
      if (visibleAtRest ||
          (remaining >= _stageCosts[next] &&
              (!moving ||
                  (dev.Timeline.now >= _recentLongUntilUs &&
                      elapsed <= _budgetUs * .7)))) {
        best._advance();
        _previousStage = next;
      }
    }
    _sleepingForTouch =
        _contact && !moving && best == null && visited == pending.length;
    _prepareAhead(deadline);
    _queue();
  }

  void dispose() {
    _visible = false;
    _lists.remove(this);
    if (_callback case final id?) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(id);
    }
    _pending.clear();
    _scan = const [];
    _measured.clear();
    _built.clear();
    geometry.clear();
    paused.dispose();
  }
}

class ProgressiveCards extends StatefulWidget {
  const ProgressiveCards({
    super.key,
    required this.preparation,
    required this.controller,
    required this.child,
  });
  final CardPreparation preparation;
  final ScrollController controller;
  final Widget child;
  @override
  State<ProgressiveCards> createState() => _ProgressiveCardsState();
}

class _ProgressiveCardsState extends State<ProgressiveCards> {
  final _motion = <(int, double)>[];
  CardPreparation get work => widget.preparation;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scroll);
    work._controller = widget.controller;
    SchedulerBinding.instance.addTimingsCallback(work._timings);

    SemanticsBinding.instance.addSemanticsEnabledListener(_semantics);
    CardPreparation._watch(work);
    if (CardShellMetrics.enabled) {
      CardShellMetrics.refresh = () {
        if (mounted) {
          for (final state in work._measured.toList()) {
            state._sample();
          }
        }
      };
      SchedulerBinding.instance.addPersistentFrameCallback((_) {
        if (!mounted || !CardShellMetrics.enabled) return;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !CardShellMetrics.enabled) return;
          for (final state in work._measured.toList()) {
            state._sample();
          }
        });
      });
    }
  }

  void _semantics() {
    if (work.accessible) {
      for (final state in work._pending.toList()) {
        state._advance(complete: true);
      }
    }
  }

  void _scroll() {
    if (!widget.controller.hasClients) return;
    final position = widget.controller.position;
    final now = dev.Timeline.now;
    work._moving = position.isScrollingNotifier.value;
    work._lastMotionUs = now;
    work._motionRevision++;
    if (!work._aheadDirty) work._aheadCursor = 0;
    work._aheadDirty = true;
    _motion.add((now, position.pixels));
    while (_motion.length > 2 && now - _motion[1].$1 > 75000) {
      _motion.removeAt(0);
    }
    final first = _motion.first;
    if (now > first.$1) {
      final delta = position.pixels - first.$2;
      work.speed = delta.abs() * 1000000 / (now - first.$1);
      if (delta != 0) work.direction = delta.sign;
    }
    work.viewport = position.viewportDimension;
    work._queue();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    if (visible && !work._visible) work.paused.value = false;
    work._visible = visible;
    work._context = context;
    work._queue();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scroll);
    SchedulerBinding.instance.removeTimingsCallback(work._timings);
    // The owner may retain this preparation object beyond the viewport. Stop
    // both queued work and an already pending post-frame continuation on detach.
    work._visible = false;
    if (work._callback case final id?) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(id);
      work._callback = null;
    }
    work._controller = null;
    SemanticsBinding.instance.removeSemanticsEnabledListener(_semantics);
    CardPreparation._lists.remove(work);
    work._context = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _CardPreparationScope(
    work: work,
    child: Listener(
      onPointerDown: (_) {
        work._contact = true;
      },
      onPointerUp: (_) {
        work._contact = false;
        work._queue();
      },
      onPointerCancel: (_) {
        work._contact = false;
        work._queue();
      },
      child: NotificationListener<ScrollEndNotification>(
        onNotification: (notification) {
          if (notification.depth == 0) {
            work.speed = 0;
            work._moving = false;
            _motion.clear();
            work._queue();
          }
          return false;
        },
        child: widget.child,
      ),
    ),
  );
}

class _CardPreparationScope extends InheritedWidget {
  const _CardPreparationScope({required this.work, required super.child});
  final CardPreparation work;
  @override
  bool updateShouldNotify(_CardPreparationScope oldWidget) =>
      !identical(work, oldWidget.work);
}

class ProgressiveCard extends StatefulWidget {
  @visibleForTesting
  static int? Function(RecipeSummary)? debugStageForRecipe;
  const ProgressiveCard({
    super.key,
    required this.recipe,
    required this.grid,
    required this.builder,
    this.forcedStage,
  });
  final RecipeSummary recipe;
  final bool grid;
  final int? forcedStage;
  final Widget Function(BuildContext, int, CardGeometry?) builder;
  @override
  State<ProgressiveCard> createState() => _ProgressiveCardState();
}

class _ProgressiveCardState extends State<ProgressiveCard> {
  final _mountId = CardShellMetrics.enabled ? CardShellMetrics.nextMount++ : 0;
  CardPreparation? _work;
  int? _stage;
  CardGeometry? _geometry;
  final _testGeometry = CardGeometryCache();
  bool _counted = false;
  bool _nativeOnly = false;
  bool _automatic = false;
  void _sample() {
    if (!mounted) return;
    final rect = _rect;
    if (rect == null) return;
    final viewport = _work?._context?.findRenderObject();
    final window = viewport is RenderBox && viewport.hasSize
        ? viewport.localToGlobal(Offset.zero) & viewport.size
        : Offset.zero & MediaQuery.sizeOf(context);
    var keptAlive = false;
    RenderObject? ancestor = context.findRenderObject();
    while (ancestor != null) {
      final data = ancestor.parentData;
      if (data is SliverMultiBoxAdaptorParentData && data.keptAlive) {
        keptAlive = true;
        break;
      }
      ancestor = ancestor.parent;
    }
    final visible = !keptAlive && rect.overlaps(window);
    CardShellMetrics.sample(
      widget.recipe.id,
      rect.height,
      _stage ?? 4,
      visible,
      _work?.fast ?? false,
      _mountId,
    );
    if (_stage == 4) _work?._measured.remove(this);
  }

  Rect? get _rect {
    final render = context.findRenderObject();
    if (render is! RenderBox || !render.hasSize || !render.attached) {
      return null;
    }
    return render.localToGlobal(Offset.zero) & render.size;
  }

  RenderObject? _sliverChild;
  RenderBox? _cardRender;
  int _rectFrame = -1;
  Rect? _frameRect;
  Rect? get _buildRect {
    if (!mounted) return null;
    final frame =
        SchedulerBinding.instance.currentFrameTimeStamp.inMicroseconds;
    if (_rectFrame == frame) return _frameRect;
    _rectFrame = frame;
    _frameRect = null;
    if (_cardRender == null || !_cardRender!.attached) {
      final render = context.findRenderObject();
      if (render is! RenderBox) return null;
      _cardRender = render;
      _sliverChild = null;
      RenderObject? ancestor = render;
      while (ancestor != null) {
        if (ancestor.parentData is SliverMultiBoxAdaptorParentData) {
          _sliverChild = ancestor;
          break;
        }
        ancestor = ancestor.parent;
      }
    }
    final data = _sliverChild?.parentData;
    if (data is SliverMultiBoxAdaptorParentData && data.keptAlive) return null;
    final render = _cardRender!;
    if (!render.hasSize || !render.attached) return null;
    return _frameRect = render.localToGlobal(Offset.zero) & render.size;
  }

  void _advance({bool complete = false}) {
    if (!mounted || _stage == 4) return;
    setState(() => _stage = complete ? 4 : (_stage ?? 0) + 1);
    if (_stage == 4) {
      _work?._pending.remove(this);
    }
  }

  @override
  void dispose() {
    _work?._pending.remove(this);
    if (_work case final work?) {
      work._built.remove(this);
      work._motionRevision++;
      work._aheadDirty = true;
    }
    _testGeometry.clear();
    _work?._measured.remove(this);
    CardShellMetrics.departed(widget.recipe.id, _mountId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _work = context
        .dependOnInheritedWidgetOfExactType<_CardPreparationScope>()
        ?.work;
    if (_work case final work?) {
      if (work._built.add(this)) {
        work._motionRevision++;
        work._aheadDirty = true;
      }
    }
    final forced =
        widget.forcedStage ??
        ProgressiveCard.debugStageForRecipe?.call(widget.recipe);
    if (!CardGeometryCache.supports(context)) {
      // Also release an existing shell when accessibility settings change.
      _stage = 4;
      _nativeOnly = true;
      _geometry = null;
      _work?._pending.remove(this);
    }
    if (_stage == null &&
        (forced == 4 || (forced == null && (_work == null || _work!._full)))) {
      _stage = 4;
      _nativeOnly = true;
    }
    if (_nativeOnly) {
      if (!_counted) {
        _counted = true;

        CardShellMetrics.created(widget.recipe.id, false, _mountId);
      }
      final child = widget.builder(
        context,
        4,
        _work?.jumping == true ? _work!.geometry.prepared(widget.recipe) : null,
      );
      return child;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final work = _work;
        final forced =
            widget.forcedStage ??
            ProgressiveCard.debugStageForRecipe?.call(widget.recipe);
        _automatic = forced == null;
        if (forced case final stage?) {
          _stage = stage;
        } else {
          _stage ??= work == null || work._full ? 4 : 0;
        }
        if (_stage! < 4 || _geometry != null) {
          _geometry = work?._configured == true
              ? work!.geometry.measurePrepared(widget.recipe)
              : (work?.geometry ?? _testGeometry).measure(
                  context,
                  widget.recipe,
                  constraints.maxWidth,
                  grid: widget.grid,
                  fixedHeight: constraints.hasBoundedHeight
                      ? constraints.maxHeight
                      : null,
                );
          if (_geometry == null) {
            _stage = 4;
          }
        }
        if (!_counted) {
          _counted = true;
          CardShellMetrics.created(widget.recipe.id, _stage! < 4, _mountId);
          if (CardShellMetrics.enabled && _stage! < 4) {
            work?._measured.add(this);
          }
        }
        if (_stage == 4) {
          work?._pending.remove(this);
        } else if (forced == null) {
          work?._pending.add(this);
          work?._queue();
        }
        final child = widget.builder(context, _stage!, _geometry);
        return SizedBox(height: _geometry?.height, child: child);
      },
    );
  }
}

/// Opt-in profile counters. Shipping builds do no per-frame observation.
class CardShellMetrics {
  static bool enabled = false;
  static int nextMount = 0;
  static void Function()? refresh;
  static final _mounts = <String, int>{};
  static final _live = <String>{};
  static int peakLive = 0, repeatFull = 0, repeatShell = 0;
  static int retained = 0, peakRetained = 0;
  static final _created = <String, bool>{};
  static final _seen = <String, Map<String, Object?>>{};
  static void reset() {
    _created.clear();
    _seen.clear();
    _mounts.clear();
    _live.clear();
    peakLive = repeatFull = repeatShell = retained = peakRetained = 0;
    nextMount = 0;
  }

  static void created(String id, bool shell, int mount) {
    if (!enabled) return;
    final key = '$id#$mount';
    _created[key] = shell;
    if ((_mounts[id] ?? 0) > 0) {
      if (shell) {
        repeatShell++;
      } else {
        repeatFull++;
      }
    }
    _mounts[id] = (_mounts[id] ?? 0) + 1;
    _live.add(key);
    peakLive = math.max(peakLive, _live.length);
  }

  static void retention(int weight) {
    if (!enabled) return;
    retained = weight;
    peakRetained = math.max(peakRetained, weight);
  }

  static void departed(String id, int mount) {
    if (!enabled) return;
    final key = '$id#$mount';
    _live.remove(key);
    final record = _seen[key];
    if (record != null) {
      record['visible'] = false;
      record['disposedUs'] = dev.Timeline.now;
    }
  }

  static void sample(
    String id,
    double height,
    int stage,
    bool visible,
    bool fast,
    int mount,
  ) {
    if (!enabled) return;
    final now = dev.Timeline.now;
    final key = '$id#$mount';
    if (visible && stage < 4) {
      _seen.putIfAbsent(
        key,
        () => {
          'id': id,
          'mount': mount,
          'firstVisibleUs': now,
          'initialHeight': height,
        },
      );
    }
    final record = _seen[key];
    if (record == null) return;
    record['visible'] = visible;
    record['lastSampleUs'] = now;
    if (visible && !fast) record.putIfAbsent('slowSinceUs', () => now);
    if (fast) record.remove('slowSinceUs');
    if (stage == 4 && !record.containsKey('finishedUs')) {
      record['finishedUs'] = now;
      record['heightChange'] = height - (record['initialHeight'] as double);
      if (record['slowSinceUs'] case final int since) {
        record['finishAfterSlowMs'] = (now - since) / 1000;
      }
    }
  }

  static Map<String, Object?> snapshot() {
    refresh?.call();
    final completed = _seen.values
        .where((r) => r['finishedUs'] != null)
        .toList();
    final durations =
        completed
            .map(
              (r) =>
                  ((r['finishedUs'] as int) - (r['firstVisibleUs'] as int)) /
                  1000,
            )
            .toList()
          ..sort();
    return {
      'liveCards': _live.length,
      'peakLiveCards': peakLive,
      'repeatFullMounts': repeatFull,
      'repeatShellMounts': repeatShell,
      'retainedWeight': retained,
      'peakRetainedWeight': peakRetained,
      'newCards': _created.length,
      'createdShells': _created.values.where((v) => v).length,
      'shellsReachedScreen': _seen.length,
      'completed': completed.length,
      'unfinished': _seen.length - completed.length,
      'unfinishedVisible': _seen.values
          .where((r) => r['finishedUs'] == null && r['visible'] == true)
          .length,
      'medianUnfinishedMs': durations.isEmpty
          ? 0
          : (durations[(durations.length - 1) ~/ 2] +
                    durations[durations.length ~/ 2]) /
                2,
      'worstUnfinishedMs': durations.isEmpty ? 0 : durations.last,
      'sizeChanges': completed
          .where((r) => (r['heightChange'] as double).abs() > 0.000001)
          .length,
      'records': [for (final record in _seen.values) Map.of(record)],
    };
  }
}
