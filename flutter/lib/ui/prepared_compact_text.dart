import 'dart:collection';
import 'dart:developer' as dev;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../src/rust/api.dart';
import '../interaction_idle.dart';
import '../tag_labels.dart';
import 'prepared_card_title.dart';
import 'progressive_cards.dart';

class CompactParagraphs {
  CompactParagraphs(this.title, this.tags, this.tagLabel);
  final PreparedTitle title;
  final PreparedTitle? tags;
  final String tagLabel;

  void release() {
    title.releaseCache();
    tags?.releaseCache();
  }
}

/// Paragraphs only; rows retain their ordinary layout, controls and semantics.
/// Mounted paragraphs own leases independently of this 128-recipe cache.
class CompactTextPreparation {
  static const capacity = 128;
  final _cache = LinkedHashMap<RecipeSummary, CompactParagraphs>.identity();
  final _indices = HashMap<RecipeSummary, int>.identity();
  List<RecipeSummary> _recipes = const [];
  Object? _environment;
  late TextStyle _titleStyle, _tagStyle;
  late TextScaler _scaler;
  late TextDirection _direction;
  Locale? _locale;
  TextHeightBehavior? _height;
  double _width = 0;
  bool supported = false;
  int revision = 0, _anchor = 0, _cursor = 0;
  int direction = 1;
  void Function()? wake;

  @visibleForTesting
  int get cachedRecipes => _cache.length;
  @visibleForTesting
  int preparedParagraphs = 0;

  void configure(
    BuildContext context,
    List<RecipeSummary> recipes,
    double width,
  ) {
    final theme = Theme.of(context);
    final defaults = DefaultTextStyle.of(context);
    final environment = (
      width,
      theme.textTheme,
      theme.colorScheme,
      defaults.style,
      MediaQuery.textScalerOf(context),
      Directionality.of(context),
      Localizations.maybeLocaleOf(context),
      DefaultTextHeightBehavior.maybeOf(context),
      CardGeometryCache.supports(context),
    );
    if (_environment != environment) {
      invalidate();
      _environment = environment;
      supported = environment.$9 && width > 0;
      _width = width;
      _titleStyle = defaults.style.merge(
        theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      );
      _tagStyle = defaults.style.merge(
        theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
      _scaler = environment.$5;
      _direction = environment.$6;
      _locale = environment.$7;
      _height = environment.$8;
    }
    if (!identical(_recipes, recipes)) {
      final previous = _recipes.isEmpty
          ? null
          : _recipes[_anchor.clamp(0, _recipes.length - 1)].id;
      _recipes = recipes;
      _indices.clear();
      for (var i = 0; i < recipes.length; i++) {
        _indices[recipes[i]] = i;
      }
      for (final old
          in _cache.keys.where((r) => !_indices.containsKey(r)).toList()) {
        _cache.remove(old)!.release();
      }
      _anchor = math.max(0, recipes.indexWhere((r) => r.id == previous));
      _cursor = 0;
      revision++;
    }
  }

  void invalidate() {
    for (final value in _cache.values) {
      value.release();
    }
    _cache.clear();
    _cursor = 0;
    revision++;
  }

  CompactParagraphs? lookup(RecipeSummary recipe) {
    final index = _indices[recipe];
    if (index != null && index != _anchor) {
      _anchor = index;
      _cursor = 0;
      wake?.call();
    }
    return supported ? _cache[recipe] : null;
  }

  void changedDirection(int value) {
    if (direction == value) return;
    direction = value;
    _cursor = 0;
  }

  bool get pending => supported && _recipes.isNotEmpty && _cursor < 96;

  /// One bounded paragraph pair. Called only in unused time at rest; never
  /// synchronously from a row build, pointer callback or hit test.
  void prepareNext() {
    if (!pending) return;
    final step = _cursor++;
    final index =
        _anchor + (step < 64 ? step * direction : -(step - 63) * direction);
    if (index < 0 || index >= _recipes.length) return;
    final recipe = _recipes[index];
    if (_cache.containsKey(recipe)) return;
    PreparedTitle paragraph(String text, TextStyle style) {
      preparedParagraphs++;
      return PreparedTitle(
        TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: _direction,
          textScaler: _scaler,
          maxLines: 1,
          ellipsis: '…',
          locale: _locale,
          textHeightBehavior: _height,
        )..layout(maxWidth: _width),
        maxWidth: _width,
      );
    }

    // Imported recipes may legally contain thousands of tags. Preparation is
    // optional: keep their ordinary Text path instead of doing unbounded work
    // for off-screen content in an otherwise idle frame.
    final prepareTags =
        recipe.tags.length <= 32 &&
        recipe.tags.fold<int>(0, (n, tag) => n + tag.length + 3) <= 2048;
    final tags = prepareTags ? normalizeTags(recipe.tags).join(' · ') : '';
    _cache[recipe] = CompactParagraphs(
      paragraph(recipe.title, _titleStyle),
      !prepareTags || recipe.tags.isEmpty ? null : paragraph(tags, _tagStyle),
      tags,
    );
    if (_cache.length > capacity) _cache.remove(_cache.keys.first)!.release();
  }

  void dispose() {
    wake = null;
    invalidate();
    _recipes = const [];
    _indices.clear();
  }
}

class PreparedCompactText extends StatefulWidget {
  const PreparedCompactText({
    super.key,
    required this.work,
    required this.controller,
    required this.enabled,
    required this.child,
  });
  final CompactTextPreparation work;
  final ScrollController controller;
  final bool enabled;
  final Widget child;

  static CompactTextPreparation? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CompactTextScope>()?.work;

  @override
  State<PreparedCompactText> createState() => _PreparedCompactTextState();
}

class _PreparedCompactTextState extends State<PreparedCompactText> {
  final _pointers = <int>{};
  int? _callback;
  bool _postPending = false, _visible = true;
  double _pixels = 0;
  Animation<double>? _route;
  int _generation = 0;

  bool get _idle =>
      mounted &&
      widget.enabled &&
      _visible &&
      !InteractionIdle.instance.busy &&
      _pointers.isEmpty &&
      (_route == null || _route!.status == AnimationStatus.completed) &&
      widget.controller.hasClients &&
      !widget.controller.position.isScrollingNotifier.value;

  @override
  void initState() {
    super.initState();
    widget.work.wake = _queue;
    widget.controller.addListener(_scroll);
    PaintingBinding.instance.systemFonts.addListener(_fonts);
  }

  void _fonts() {
    widget.work.invalidate();
    if (mounted) setState(() {});
    _queue();
  }

  void _scroll() {
    if (!widget.controller.hasClients) return;
    final pixels = widget.controller.offset;
    if (pixels != _pixels) {
      widget.work.changedDirection(pixels > _pixels ? 1 : -1);
    }
    _pixels = pixels;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    final route = ModalRoute.of(context)?.animation;
    if (!identical(route, _route)) {
      _route?.removeStatusListener(_transition);
      _route = route;
      _route?.addStatusListener(_transition);
    }
    _queue();
  }

  void _transition(AnimationStatus _) => _queue();

  @override
  void didUpdateWidget(PreparedCompactText oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(identical(oldWidget.work, widget.work));
    assert(identical(oldWidget.controller, widget.controller));
    _queue();
  }

  void _queue() {
    if (mounted &&
        widget.enabled &&
        _visible &&
        widget.work.pending &&
        InteractionIdle.instance.busy) {
      InteractionIdle.instance.runWhenIdle(this, _queue);
      return;
    }
    if (!_idle || !widget.work.pending || _callback != null || _postPending) {
      return;
    }
    final generation = _generation;
    _callback = SchedulerBinding.instance.scheduleFrameCallback((_) {
      _callback = null;
      if (generation != _generation) return;
      if (!_idle) {
        _queue();
        return;
      }
      final started = dev.Timeline.now;
      final rawFrameStart =
          SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds;
      // Real engine frame timestamps include earlier transient callbacks. The
      // widget-test fake clock can occupy a different time domain.
      final frameStart =
          started >= rawFrameStart && started - rawFrameStart < 1000000
          ? rawFrameStart
          : started;
      _postPending = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _postPending = false;
        if (generation != _generation) return;
        if (!_idle) {
          _queue();
          return;
        }
        final hz = View.of(context).display.refreshRate;
        final now = dev.Timeline.now;
        final deadline = math.min(
          frameStart + (1000000 / (hz > 0 ? hz : 60) * .8).floor(),
          now + 1500,
        );
        // Leave room for the next bounded paragraph pair. Paragraph layout is
        // indivisible, so this is a cooperative budget, not a real-time limit.
        for (
          var count = 0;
          count < 2 && widget.work.pending && dev.Timeline.now + 700 < deadline;
          count++
        ) {
          widget.work.prepareNext();
        }
        _queue();
      });
    });
  }

  @override
  void dispose() {
    _generation++;
    InteractionIdle.instance.cancel(this);
    if (_callback case final id?) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(id);
    }
    widget.work.wake = null;
    widget.controller.removeListener(_scroll);
    _route?.removeStatusListener(_transition);
    PaintingBinding.instance.systemFonts.removeListener(_fonts);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _CompactTextScope(
    work: widget.work,
    revision: widget.work.revision,
    child: Listener(
      onPointerDown: (event) => _pointers.add(event.pointer),
      onPointerUp: (event) {
        _pointers.remove(event.pointer);
        _queue();
      },
      onPointerCancel: (event) {
        _pointers.remove(event.pointer);
        _queue();
      },
      child: NotificationListener<ScrollEndNotification>(
        onNotification: (notification) {
          if (notification.depth == 0) {
            // ScrollEnd precedes the activity switch. Queue after layout,
            // when the live position can confirm that the list has settled.
            SchedulerBinding.instance.addPostFrameCallback((_) => _queue());
          }
          return false;
        },
        child: widget.child,
      ),
    ),
  );
}

class _CompactTextScope extends InheritedWidget {
  const _CompactTextScope({
    required this.work,
    required this.revision,
    required super.child,
  });
  final CompactTextPreparation work;
  final int revision;
  @override
  bool updateShouldNotify(_CompactTextScope oldWidget) =>
      revision != oldWidget.revision;
}
