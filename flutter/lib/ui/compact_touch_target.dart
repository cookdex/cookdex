import 'dart:async';

import 'package:flutter/material.dart';

/// Touch-only Library controls. Feedback exists only for an actual press and is
/// painted locally beneath its content, without idle Material/focus machinery.
class CompactTouchTarget extends StatefulWidget {
  const CompactTouchTarget({
    super.key,
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.favoriteLabel,
    this.trailingControl = false,
    this.card = false,
    this.cornerRadius = 0,
  });
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? favoriteLabel;
  final bool trailingControl;
  final bool card;
  final double cornerRadius;
  final Widget child;

  @override
  State<CompactTouchTarget> createState() => _CompactTouchTargetState();
}

enum _PressPhase { held, released }

class _CompactTouchTargetState extends State<CompactTouchTarget> {
  ValueNotifier<_PressPhase>? _phase;
  ScrollPosition? _position;
  Offset _pressPosition = Offset.zero;
  bool _holding = false;

  void _clear({bool rebuild = true}) {
    _position?.isScrollingNotifier.removeListener(_scrollChanged);
    _position = null;
    final phase = _phase;
    _phase = null;
    phase?.dispose();
    if (phase != null && rebuild && mounted) setState(() {});
  }

  void _scrollChanged() {
    if (_position?.isScrollingNotifier.value == true) _clear();
  }

  void _down(TapDownDetails details) {
    final box = context.findRenderObject()! as RenderBox;
    if (widget.trailingControl) {
      final control = widget.card
          ? Rect.fromLTWH(box.size.width - 52, 10, 48, 48)
          : Rect.fromLTWH(
              Directionality.of(context) == TextDirection.rtl
                  ? 0
                  : box.size.width - 48,
              (box.size.height - 49) / 2,
              48,
              48,
            );
      if (control.contains(box.globalToLocal(details.globalPosition))) return;
    }
    _clear(rebuild: false);
    _holding = false;
    _pressPosition = box.globalToLocal(details.globalPosition);
    setState(() => _phase = ValueNotifier(_PressPhase.held));
    _position = Scrollable.maybeOf(context)?.position;
    _position?.isScrollingNotifier.addListener(_scrollChanged);
  }

  void _cancel() {
    // Long-press recognition cancels the tap in the same event. Keep its ink;
    // a drag cancellation instead removes the overlay before scrolling paints.
    final phase = _phase;
    scheduleMicrotask(() {
      if (mounted && !_holding && identical(phase, _phase)) _clear();
    });
  }

  void _tap() {
    _phase?.value = _PressPhase.released;
    Feedback.forTap(context);
    widget.onTap();
  }

  void _hold() {
    _holding = true;
    if (widget.onLongPress case final callback?) {
      Feedback.forLongPress(context);
      callback();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _clear(rebuild: false);
  }

  @override
  void deactivate() {
    _clear(rebuild: false);
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    final star = widget.favoriteLabel != null;
    final phase = _phase;
    final target = GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: star,
      onTapDown: _down,
      onTap: _tap,
      onTapCancel: _cancel,
      onLongPress: _hold,
      onLongPressCancel: () {
        _holding = false;
        _clear();
      },
      onSecondaryTap: widget.card ? widget.onLongPress : null,
      onLongPressEnd: (_) {
        _holding = false;
        _phase?.value = _PressPhase.released;
      },
      child: phase != null
          ? Material(
              key: ObjectKey(phase),
              type: MaterialType.transparency,
              borderRadius: BorderRadius.circular(widget.cornerRadius),
              clipBehavior: Clip.antiAlias,
              child: _PressInk(
                phase: phase,
                star: star,
                position: _pressPosition,
                onFinished: () {
                  if (identical(_phase, phase)) _clear();
                },
                child: widget.child,
              ),
            )
          : widget.child,
    );
    return star
        ? Semantics(
            container: true,
            button: true,
            enabled: true,
            label: widget.favoriteLabel,
            onTap: widget.onTap,
            excludeSemantics: true,
            child: target,
          )
        : target;
  }
}

/// Mounted only for a press. Uses the same theme splash/highlight as Cards did.
class _PressInk extends StatefulWidget {
  const _PressInk({
    required this.phase,
    required this.star,
    required this.position,
    required this.onFinished,
    required this.child,
  });
  final ValueNotifier<_PressPhase> phase;
  final bool star;
  final Offset position;
  final VoidCallback onFinished;
  final Widget child;
  @override
  State<_PressInk> createState() => _PressInkState();
}

class _PressInkState extends State<_PressInk> {
  InteractiveInkFeature? _splash;
  InkHighlight? _highlight;
  bool _started = false, _closing = false;
  @override
  void initState() {
    super.initState();
    widget.phase.addListener(_release);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final theme = Theme.of(context);
      final box = context.findRenderObject()! as RenderBox;
      final controller = Material.of(context);
      _splash = theme.splashFactory.create(
        controller: controller,
        referenceBox: box,
        position: widget.position,
        color: widget.star
            ? theme.colorScheme.onSurfaceVariant.withValues(alpha: .1)
            : theme.splashColor,
        textDirection: Directionality.of(context),
        containedInkWell: true,
        rectCallback: () => Offset.zero & box.size,
        customBorder: widget.star ? const StadiumBorder() : null,
        onRemoved: () {
          _splash = null;
          _finishIfDone();
        },
      );
      if (!widget.star) {
        _highlight = InkHighlight(
          controller: controller,
          referenceBox: box,
          color: theme.highlightColor,
          shape: BoxShape.rectangle,
          textDirection: Directionality.of(context),
          onRemoved: () {
            _highlight = null;
            _finishIfDone();
          },
        );
      }
      _started = true;
      _release();
    });
  }

  void _release() {
    if (widget.phase.value != _PressPhase.released) return;
    _splash?.confirm();
    _highlight?.deactivate();
    _finishIfDone();
  }

  void _finishIfDone() {
    if (!_closing &&
        _started &&
        _splash == null &&
        _highlight == null &&
        widget.phase.value == _PressPhase.released) {
      _closing = true;
      // A release can arrive from ValueNotifier.notifyListeners. Its owner
      // must not dispose that notifier until the notification has returned.
      scheduleMicrotask(() {
        if (mounted) widget.onFinished();
      });
    }
  }

  @override
  void dispose() {
    _closing = true;
    widget.phase.removeListener(_release);
    _splash?.dispose();
    _highlight?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
