import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/scheduler.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Starts the finish flash and releases the result at its 420 ms handoff.
class SmartActionButtonController {
  _SmartActionButtonState? _button;

  Future<void> flash() async {
    await _button?._playFlash();
  }
}

class SmartActionButton extends StatefulWidget {
  const SmartActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.phase,
    this.onCancel,
    this.outlined = false,
    this.minHeight = 48,
    this.icon = Symbols.auto_awesome,
    this.controller,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? phase;
  final VoidCallback? onCancel;
  final bool outlined;
  final double minHeight;
  final IconData icon;
  final SmartActionButtonController? controller;

  @override
  State<SmartActionButton> createState() => _SmartActionButtonState();
}

class _SmartActionButtonState extends State<SmartActionButton>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _fx = _ButtonEffects();
  final _layoutFrame = ValueNotifier(0.0);
  double _clockBase = 0, _layoutUntil = 0;
  double _disabledFrom = 0, _disabledTo = 0, _disabledStart = 0;
  double _phraseStart = -1000;
  late String _oldLabel, _label;
  late SmartWorkingColors _colors;
  Color? _seed;
  bool _reduceMotion = false;
  Offset? _tap;
  Timer? _qualification, _minimumRead, _reminder, _navigationTimer;
  Completer<void>? _navigation;
  String? _qualified;
  bool get _working => widget.phase != null;
  bool get _disabled => !_working && widget.onPressed == null;
  double get _disabledAmount => _reduceMotion
      ? _disabledTo
      : ui.lerpDouble(
          _disabledFrom,
          _disabledTo,
          Curves.ease.transform(_unit((_fx.now - _disabledStart) / 200)),
        )!;

  @override
  void initState() {
    super.initState();
    _oldLabel = _label = widget.phase ?? widget.label;
    _disabledFrom = _disabledTo = _disabled ? 1 : 0;
    widget.controller?._button = this;
    if (_working) {
      _fx.start(null);
      _layoutUntil = 420;
      _holdLabel();
      _scheduleReminder();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateColors();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _oldLabel = _label;
      _phraseStart = -1000;
      if (!_working) _fx.clear();
      _releaseNavigation();
    }
    _syncTicker();
  }

  void _updateColors() {
    final scheme = Theme.of(context).colorScheme;
    final richerFill = !widget.outlined;
    if (_seed == scheme.tertiary &&
        _colors.brightness == scheme.brightness &&
        _colors.richerFill == richerFill) {
      return;
    }
    _seed = scheme.tertiary;
    _colors = SmartWorkingColors(
      scheme.tertiary,
      scheme.brightness,
      richerFill: richerFill,
    );
  }

  @override
  void didUpdateWidget(SmartActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.outlined != oldWidget.outlined) _updateColors();
    final disabledTarget = _disabled ? 1.0 : 0.0;
    if (disabledTarget != _disabledTo) {
      _disabledFrom = _disabledAmount;
      _disabledTo = disabledTarget;
      _disabledStart = _fx.now;
      _layoutUntil = math.max(_layoutUntil, _fx.now + 200);
      _syncTicker();
    }
    if (widget.controller != oldWidget.controller) {
      if (oldWidget.controller?._button == this) {
        oldWidget.controller?._button = null;
      }
      widget.controller?._button = this;
    }
    if (widget.phase == oldWidget.phase) {
      if (!_working && oldWidget.label != widget.label) _setLabel(widget.label);
      return;
    }
    _qualification?.cancel();
    _qualified = null;
    _reminder?.cancel();
    if (!_working) {
      _minimumRead?.cancel();
      // A cancelled operation leaves without a finish flash. A successful
      // result may cover this button while the last 130 ms are still painting.
      _fx.end(cancelFlash: _navigation != null);
      _releaseNavigation();
      if (_reduceMotion) _fx.clear();
      _setLabel(widget.label);
    } else if (oldWidget.phase == null) {
      _fx.start(_tap);
      _tap = null;
      _setLabel(widget.phase!);
      _holdLabel();
    } else if (_fx.flashAt == null) {
      final phase = widget.phase!;
      _qualification = Timer(const Duration(milliseconds: 800), () {
        _qualified = phase;
        _promote();
      });
    }
    if (_working && _fx.flashAt == null) _scheduleReminder();
    _syncTicker();
  }

  // Eligibility counts from the actual phase change. A short phase can
  // disappear or finish freely while a longer one waits for the current read.
  void _promote() {
    final next = _qualified;
    if (next == null || !_working || _minimumRead?.isActive == true) return;
    _qualified = null;
    setState(() => _setLabel(next));
    _holdLabel();
  }

  void _holdLabel() {
    _minimumRead?.cancel();
    final entering = !_reduceMotion && _oldLabel != _label;
    _minimumRead = Timer(
      Duration(milliseconds: entering ? 1110 : 1000),
      _promote,
    );
  }

  void _scheduleReminder() {
    _reminder = Timer(const Duration(seconds: 15), () {
      _qualified = 'Still working on it…';
      _promote();
    });
  }

  void _setLabel(String next) {
    if (_label == next) return;
    _oldLabel = _reduceMotion ? next : _visibleLabel;
    _label = next;
    _phraseStart = _fx.now;
    _layoutUntil = _fx.now + 420;
    _syncTicker();
  }

  String get _visibleLabel => _fx.now - _phraseStart < 110 ? _oldLabel : _label;

  void _syncTicker() {
    if (_reduceMotion || (!_fx.visible && _fx.now >= _layoutUntil)) {
      if (_ticker.isActive) _ticker.stop();
    } else if (!_ticker.isActive) {
      _clockBase = _fx.now;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final before = _fx.now;
    _fx.advance(_clockBase + elapsed.inMicroseconds / 1000);
    if (before <= _layoutUntil || !_fx.visible) _layoutFrame.value = _fx.now;
    _syncTicker();
  }

  Future<void> _playFlash() {
    if (!_working || !mounted) return Future.value();
    _qualification?.cancel();
    _reminder?.cancel();
    _minimumRead?.cancel();
    _qualified = null;
    if (_reduceMotion) return Future.value();
    final pending = _navigation;
    if (pending != null) return pending.future;
    _fx.flashAt = _fx.now;
    final navigation = _navigation = Completer<void>();
    _navigationTimer = Timer(
      const Duration(milliseconds: 420),
      _releaseNavigation,
    );
    return navigation.future;
  }

  void _releaseNavigation() {
    _navigationTimer?.cancel();
    _navigation?.complete();
    _navigation = null;
  }

  @override
  void dispose() {
    if (widget.controller?._button == this) widget.controller?._button = null;
    _releaseNavigation();
    _qualification?.cancel();
    _minimumRead?.cancel();
    _reminder?.cancel();
    _ticker.dispose();
    _fx.dispose();
    _layoutFrame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final idleFill = widget.outlined ? scheme.surface : scheme.tertiary;
    final disabledFill = scheme.onSurface.withValues(alpha: .12);
    final disabledInk = scheme.onSurface.withValues(alpha: .38);
    final textStyle = Theme.of(context).textTheme.labelLarge!.copyWith(
      fontSize: widget.minHeight > 48 ? 17 : 15,
      fontWeight: FontWeight.w700,
    );
    double measure(String label) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = painter.width.ceilToDouble() + 1;
      painter.dispose();
      return width;
    }

    final oldWidth = measure(_oldLabel);
    final newWidth = _label == _oldLabel ? oldWidth : measure(_label);
    final iconSize = widget.minHeight > 48 ? 22.0 : 18.0;
    final hasCancel = widget.onCancel != null;
    return RepaintBoundary(
      child: Material(
        type: MaterialType.transparency,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          alignment: Alignment.center,
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _layoutFrame,
                builder: (context, _) => DecoratedBox(
                  decoration: ShapeDecoration(
                    color: widget.outlined
                        ? idleFill
                        : Color.lerp(idleFill, disabledFill, _disabledAmount),
                    shape: StadiumBorder(
                      side: widget.outlined
                          ? BorderSide(
                              color: Color.lerp(
                                scheme.outline,
                                disabledFill,
                                _disabledAmount,
                              )!,
                            )
                          : BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _WorkingPaint(
                    _colors,
                    _fx,
                    working: _working,
                    reduced: _reduceMotion,
                  ),
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _layoutFrame,
              builder: (context, _) {
                final visible = _reduceMotion ? _working : _fx.visible;
                final entering = visible && !_reduceMotion && _fx.reveal < 1;
                final fade = visible && !_reduceMotion ? _fx.opacity : 1.0;
                final idleForeground = Color.lerp(
                  widget.outlined ? scheme.primary : scheme.onTertiary,
                  disabledInk,
                  _disabledAmount,
                )!;
                final ink = !visible || entering
                    ? idleForeground
                    : fade == 1
                    ? _colors.ink
                    : _colors.entranceInk(
                        Color.lerp(idleFill, _colors.base.first, fade)!,
                      );
                final elapsed = _fx.now - _phraseStart;
                final switching =
                    !_reduceMotion && _oldLabel != _label && elapsed < 310;
                final outgoing = switching && elapsed < 110;
                final progress = switching
                    ? Curves.ease.transform(
                        _unit(outgoing ? elapsed / 110 : (elapsed - 110) / 200),
                      )
                    : 1.0;
                final opacity = outgoing ? 1 - progress : progress;
                final dy = outgoing ? -7 * progress : 7 * (1 - progress);
                final widthT = _reduceMotion
                    ? 1.0
                    : Curves.ease.transform(_unit(elapsed / 280));
                final space = visible && hasCancel
                    ? _fx.cancelFraction(260, _reduceMotion)
                    : 0.0;
                final cancelT = visible && hasCancel
                    ? _fx.cancelFraction(220, _reduceMotion)
                    : 0.0;
                final icon = Icon(
                  visible ? Symbols.auto_awesome : widget.icon,
                  size: iconSize,
                  color: widget.outlined && (!visible || entering)
                      ? Color.lerp(
                          scheme.tertiary,
                          disabledInk,
                          _disabledAmount,
                        )
                      : ink,
                );
                final content = ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: math.max(48, widget.minHeight),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox.square(
                                    dimension: iconSize,
                                    child: visible && !_reduceMotion
                                        ? Flow(
                                            delegate: _Twinkle(_fx),
                                            clipBehavior: Clip.none,
                                            children: [icon],
                                          )
                                        : icon,
                                  ),
                                  const SizedBox(width: 7),
                                  Flexible(
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        final labelWidth = outgoing
                                            ? oldWidth
                                            : newWidth;
                                        return SizedBox(
                                          width: ui.lerpDouble(
                                            oldWidth,
                                            newWidth,
                                            widthT,
                                          ),
                                          child: OverflowBox(
                                            fit: OverflowBoxFit.deferToChild,
                                            minWidth: math.min(
                                              constraints.maxWidth,
                                              labelWidth,
                                            ),
                                            maxWidth: math.min(
                                              constraints.maxWidth,
                                              labelWidth,
                                            ),
                                            child: Transform.translate(
                                              offset: Offset(0, dy),
                                              child: Opacity(
                                                opacity: opacity,
                                                child: Text(
                                                  outgoing ? _oldLabel : _label,
                                                  textAlign: TextAlign.center,
                                                  style: textStyle.copyWith(
                                                    color: ink,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(width: 48 * space),
                        ],
                      ),
                      if (hasCancel && visible)
                        Positioned(
                          right: 0,
                          top: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            ignoring: !_working,
                            child: ExcludeSemantics(
                              excluding: !_working,
                              child: Opacity(
                                opacity: cancelT,
                                child: Stack(
                                  alignment: Alignment.centerLeft,
                                  children: [
                                    SizedBox(
                                      width: 1,
                                      height: 24,
                                      child: ColoredBox(
                                        color: ink.withValues(alpha: .28),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Cancel',
                                      constraints: const BoxConstraints(
                                        minWidth: 48,
                                        minHeight: 48,
                                      ),
                                      onPressed: widget.onCancel,
                                      icon: Transform.scale(
                                        scale: .7 + .3 * cancelT,
                                        child: Icon(
                                          Symbols.close,
                                          size: 20,
                                          color: ink,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
                Widget foreground = content;
                if (entering) {
                  // The ink changes only inside the same circle as its background.
                  foreground = ShaderMask(
                    blendMode: BlendMode.srcATop,
                    shaderCallback: (bounds) {
                      final center = _fx.center(bounds.size);
                      final r = math.max(.001, _fx.radius(bounds.size));
                      return ui.Gradient.radial(
                        center,
                        r,
                        [
                          _colors.ink,
                          _colors.ink,
                          _colors.ink.withValues(alpha: 0),
                        ],
                        const [0, .999, 1],
                      );
                    },
                    child: content,
                  );
                }
                if (_working) {
                  return Semantics(
                    liveRegion: true,
                    label: _label,
                    child: foreground,
                  );
                }
                return Semantics(
                  button: true,
                  enabled: widget.onPressed != null,
                  child: Listener(
                    onPointerDown: (event) => _tap = event.localPosition,
                    onPointerCancel: (_) => _tap = null,
                    child: InkWell(
                      onTap: widget.onPressed,
                      onTapCancel: () => _tap = null,
                      splashFactory: NoSplash.splashFactory,
                      highlightColor: Colors.transparent,
                      customBorder: const StadiumBorder(),
                      child: foreground,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

double _unit(double value) => value.clamp(0.0, 1.0);

/// OKLCH hue steps from the reference, with sRGB gamut mapping at fixed lightness.
class SmartWorkingColors {
  SmartWorkingColors(
    Color tertiary,
    this.brightness, {
    this.richerFill = false,
  }) {
    final hue = _hue(tertiary);
    final dark = brightness == Brightness.dark;
    List<Color> palette(
      List<(int, double, double)> steps, {
      bool richer = false,
    }) => [
      for (final (offset, lightness, chroma) in steps)
        _color(
          hue + offset,
          richer ? lightness - (dark ? .027 : .009) : lightness,
          richer ? chroma * (dark ? 1.28 : 1.10) : chroma,
        ),
    ];
    base = palette(
      dark
          ? const [
              (0, .855, .095),
              (-6, .88, .10),
              (-31, .87, .09),
              (-52, .867, .06),
              (22, .896, .08),
              (0, .855, .095),
            ]
          : const [
              (-6, .868, .127),
              (-40, .84, .10),
              (-61, .804, .113),
              (-88, .836, .083),
              (28, .886, .083),
              (-6, .868, .127),
            ],
      richer: richerFill,
    );
    splashes = palette(
      dark
          ? const [
              (0, .95, .065),
              (-10, .89, .12),
              (-38, .855, .095),
              (-55, .82, .105),
              (-82, .875, .07),
              (29, .905, .075),
              (-3, .92, .095),
            ]
          : const [
              (-2, .91, .125),
              (-33, .853, .10),
              (-59, .795, .12),
              (-91, .832, .10),
              (31, .878, .10),
              (-8, .885, .13),
            ],
      richer: richerFill,
    );
    ring = palette(
      dark
          ? const [
              (-25, .80, .14),
              (-55, .74, .15),
              (-5, .86, .14),
              (-95, .76, .12),
              (35, .84, .11),
            ]
          : const [
              (-10, .89, .075),
              (-40, .87, .07),
              (-5, .9, .08),
              (-85, .89, .05),
              (30, .91, .06),
            ],
      richer: true,
    );
    ink = _color(hue, .27, .05);
    flash = _color(hue, .985, .025);
    inkLuminance = ink.computeLuminance();
  }

  final Brightness brightness;
  final bool richerFill;
  late final List<Color> base, splashes, ring;
  late final Color ink, flash;
  late final double inkLuminance;

  Color entranceInk(Color background) {
    final luminance = background.computeLuminance();
    if ((luminance + .05) / (inkLuminance + .05) >= 4.5) return ink;
    return (luminance + .05) / .05 >= 4.5 ? Colors.black : Colors.white;
  }

  static double _hue(Color color) {
    double linear(double c) =>
        c <= .04045 ? c / 12.92 : math.pow((c + .055) / 1.055, 2.4).toDouble();
    final r = linear(color.r), g = linear(color.g), b = linear(color.b);
    double root(double x) => math.pow(x, 1 / 3).toDouble();
    final l = root(.4122214708 * r + .5363325363 * g + .0514459929 * b);
    final m = root(.2119034982 * r + .6806995451 * g + .1073969566 * b);
    final s = root(.0883024619 * r + .2817188376 * g + .6299787005 * b);
    return math.atan2(
          .0259040371 * l + .7827717662 * m - .808675766 * s,
          1.9779984951 * l - 2.428592205 * m + .4505937099 * s,
        ) *
        180 /
        math.pi;
  }

  static Color _color(double hue, double lightness, double chroma) {
    final angle = hue * math.pi / 180;
    double cube(double x) => x * x * x;
    int channel(double x) =>
        (255 *
                (x <= .0031308
                    ? 12.92 * x
                    : 1.055 * math.pow(x, 1 / 2.4) - .055))
            .round()
            .clamp(0, 255);
    for (double c = chroma; c > 0; c -= .004) {
      final a = c * math.cos(angle), b = c * math.sin(angle);
      final l = cube(lightness + .3963377774 * a + .2158037573 * b);
      final m = cube(lightness - .1055613458 * a - .0638541728 * b);
      final s = cube(lightness - .0894841775 * a - 1.291485548 * b);
      final red = 4.0767416621 * l - 3.3077115913 * m + .2309699292 * s;
      final green = -1.2684380046 * l + 2.6097574011 * m - .3413193965 * s;
      final blue = -.0041960863 * l - .7034186147 * m + 1.707614701 * s;
      if (math.min(red, math.min(green, blue)) >= -.001 &&
          math.max(red, math.max(green, blue)) <= 1.001) {
        return Color.fromARGB(255, channel(red), channel(green), channel(blue));
      }
    }
    final grey = channel(cube(lightness));
    return Color.fromARGB(255, grey, grey, grey);
  }
}

class _Splash {
  _Splash(this.start, math.Random random)
    : x = .06 + random.nextDouble() * .88,
      y = .15 + random.nextDouble() * .70,
      diameter = 1.5 + random.nextDouble() * 1.6,
      duration = 1600 + random.nextDouble() * 900,
      hue = random.nextInt(42); // Divisible by both palette lengths.
  final double start, x, y, diameter, duration;
  final int hue;
}

// Only the paint and sparkle listen on steady working frames. The label row
// listens to the same ticker during its finite layout/ink transitions.
class _ButtonEffects extends ChangeNotifier {
  final _random = math.Random();
  final splashes = <_Splash>[];
  double now = 0, startAt = 0, _nextSplash = 0, _settleFrom = 0;
  double? endAt, flashAt;
  Offset? origin;
  bool visible = false;

  void start(Offset? tap) {
    startAt = now;
    origin = tap;
    visible = true;
    endAt = flashAt = null;
    splashes.clear();
    _spawn();
  }

  void _spawn() {
    splashes.add(_Splash(now, _random));
    _nextSplash = now + 380 + _random.nextDouble() * 420;
  }

  void end({required bool cancelFlash}) {
    _settleFrom = sparkle;
    endAt = now;
    if (cancelFlash) flashAt = null;
  }

  void clear() {
    visible = false;
    splashes.clear();
  }

  void advance(double time) {
    now = time;
    if (visible) {
      splashes.removeWhere((s) => now - s.start >= s.duration);
      if (endAt == null && flashAt == null && now >= _nextSplash) _spawn();
      if (endAt != null && now - endAt! >= 320) clear();
    }
    notifyListeners();
  }

  double get age => now - startAt;
  // A cancelled partial reveal fades from its current radius.
  double get reveal => const Cubic(
    .2,
    0,
    0,
    1,
  ).transform(_unit(((endAt ?? now) - startAt) / 420));

  Offset center(Size size) {
    final tap = origin;
    if (tap == null) return size.center(Offset.zero);
    return Offset(
      tap.dx.clamp(0.0, size.width),
      tap.dy.clamp(0.0, size.height),
    );
  }

  double radius(Size size) {
    final p = center(size);
    final dx = math.max(p.dx, size.width - p.dx);
    final dy = math.max(p.dy, size.height - p.dy);
    return (math.sqrt(dx * dx + dy * dy) + 12) * reveal;
  }

  double get opacity => endAt == null
      ? 1
      : 1 - Curves.ease.transform(_unit((now - endAt!) / 320));

  double cancelFraction(int duration, bool reduced) {
    if (reduced) return endAt == null ? 1 : 0;
    final end = endAt;
    final entrance = Curves.ease.transform(
      _unit(((end ?? now) - startAt) / duration),
    );
    return end == null
        ? entrance
        : entrance * (1 - Curves.ease.transform(_unit((now - end) / duration)));
  }

  double get sparkle {
    if (endAt != null) {
      return _settleFrom *
          (1 - Curves.easeOut.transform(_unit((now - endAt!) / 240)));
    }
    final phase = (age % 1500) / 750;
    return Curves.easeInOut.transform(_unit(phase > 1 ? 2 - phase : phase));
  }
}

class _Twinkle extends FlowDelegate {
  _Twinkle(this.fx) : super(repaint: fx);
  final _ButtonEffects fx;

  @override
  void paintChildren(FlowPaintingContext context) {
    final wave = fx.sparkle;
    final scale = 1 + .16 * wave, half = context.size.width / 2;
    final matrix = Matrix4.identity()
      ..translateByDouble(half, half, 0, 1)
      ..rotateZ(14 * math.pi / 180 * wave)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-half, -half, 0, 1);
    context.paintChild(0, transform: matrix);
  }

  @override
  bool shouldRepaint(_Twinkle old) => fx != old.fx;
}

class _WorkingPaint extends CustomPainter {
  _WorkingPaint(
    this.colors,
    this.fx, {
    required this.working,
    required this.reduced,
  }) : super(repaint: fx);

  final SmartWorkingColors colors;
  final _ButtonEffects fx;
  final bool working, reduced;
  static const bloom = Cubic(.2, .7, .3, 1);
  static final _axis = Offset(
    math.sin(100 * math.pi / 180),
    -math.cos(100 * math.pi / 180),
  );

  ui.Shader _linear(Rect rect, List<Color> palette) {
    final half = _axis * ((rect.width * _axis.dx + rect.height * _axis.dy) / 2);
    return ui.Gradient.linear(rect.center - half, rect.center + half, palette, [
      for (var i = 0; i < palette.length; i++) i / (palette.length - 1),
    ]);
  }

  late final _splashShaders = [
    for (final color in colors.splashes)
      ui.Gradient.radial(
        Offset.zero,
        math.sqrt2,
        [color, color, color.withValues(alpha: 0)],
        const [0, .32, .70],
      ),
  ];
  late final _flashShader = ui.Gradient.radial(
    Offset.zero,
    math.sqrt2,
    [colors.flash, colors.flash, colors.flash.withValues(alpha: 0)],
    const [0, .25, .62],
  );
  Size? _lastSize;
  late ui.Shader _base, _sheen;

  void _disk(
    Canvas canvas,
    Offset center,
    double radius,
    ui.Shader shader,
    double opacity,
  ) {
    if (radius <= 0 || opacity <= 0) return;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(radius);
    canvas.drawCircle(
      Offset.zero,
      1,
      Paint()
        ..shader = shader
        ..color = Colors.white.withValues(alpha: opacity),
    );
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (!(reduced ? working : fx.visible) || size.isEmpty) return;
    final rect = Offset.zero & size;
    final field = reduced
        ? rect
        : Rect.fromLTWH(0, 0, size.width * 4.2, size.height);
    if (_lastSize != size) {
      _base = _linear(field, colors.base);
      _sheen = _linear(Rect.fromLTWH(0, 0, size.width * .55, size.height), [
        Colors.white.withValues(alpha: 0),
        Colors.white.withValues(
          alpha: colors.brightness == Brightness.dark ? .50 : .60,
        ),
        Colors.white.withValues(alpha: 0),
      ]);
      _lastSize = size;
    }
    canvas.save();
    if (!reduced && fx.reveal < 1) {
      canvas.clipPath(
        Path()..addOval(
          Rect.fromCircle(center: fx.center(size), radius: fx.radius(size)),
        ),
      );
    }
    final fade = reduced ? 1.0 : fx.opacity;
    if (fade < 1) {
      canvas.saveLayer(
        rect,
        Paint()..color = Colors.white.withValues(alpha: fade),
      );
    }
    final cycle = reduced ? 0.0 : (fx.age % 14000) / 7000;
    final drift = Curves.easeInOut.transform(
      _unit(cycle > 1 ? 2 - cycle : cycle),
    );
    canvas.save();
    canvas.translate(-size.width * 3.2 * drift, 0);
    canvas.drawRect(field, Paint()..shader = _base);
    canvas.restore();
    if (!reduced) {
      for (final splash in fx.splashes) {
        final t = _unit((fx.now - splash.start) / splash.duration);
        final alpha =
            .85 *
            (t < .22
                ? bloom.transform(_unit(t / .22))
                : 1 - bloom.transform(_unit((t - .22) / .78)));
        _disk(
          canvas,
          Offset(size.width * splash.x, size.height * splash.y),
          size.height * splash.diameter / 2 * (.15 + 1.10 * bloom.transform(t)),
          _splashShaders[splash.hue % _splashShaders.length],
          alpha,
        );
      }
      final sweep = (fx.age % 2800) / 1960;
      if (sweep < 1) {
        canvas.save();
        canvas.translate(
          size.width * (-.60 + 1.70 * Curves.easeInOut.transform(sweep)),
          0,
        );
        canvas.drawRect(
          Rect.fromLTWH(0, 0, size.width * .55, size.height),
          Paint()..shader = _sheen,
        );
        canvas.restore();
      }
    }
    final pill = RRect.fromRectAndRadius(
      rect.deflate(.75),
      Radius.circular(size.height / 2),
    );
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..shader = SweepGradient(
        colors: [...colors.ring, colors.ring.first],
        transform: GradientRotation(
          reduced ? 0 : (fx.age % 3200) * math.pi / 1600,
        ),
      ).createShader(rect);
    canvas.drawRRect(pill, edge);
    final flashed = fx.flashAt;
    if (!reduced && flashed != null && fx.now - flashed < 550) {
      final p = Curves.easeOut.transform(_unit((fx.now - flashed) / 550));
      _disk(
        canvas,
        rect.center,
        size.width * .70 * (.05 + 1.05 * p),
        _flashShader,
        .95 * (1 - p),
      );
    }
    if (fade < 1) canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WorkingPaint old) =>
      colors != old.colors ||
      fx != old.fx ||
      reduced != old.reduced ||
      // A still button has no ticker to invalidate its retained paint layer.
      (reduced && working != old.working);
}
