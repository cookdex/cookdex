import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Resolves native styles and combines a display-only metadata icon and label.
/// Unsupported widget structures and typography retain the original pair.
class RecipeMetadataItem extends StatelessWidget {
  const RecipeMetadataItem({
    super.key,
    required this.icon,
    required this.text,
    this.enabled = true,
  });

  final Icon icon;
  final Text text;
  final bool enabled;

  @visibleForTesting
  static List<TextPainter>? debugPainters(RenderBox renderObject) =>
      renderObject is _RenderMetadataLeaf
      ? [renderObject._glyphPainter!, renderObject._labelPainter!]
      : null;

  Widget _native() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      icon,
      const SizedBox(width: 5),
      Flexible(child: text),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (!enabled || Directionality.of(context) != TextDirection.ltr) {
      return _native();
    }
    final resolvedIcon = icon.build(context);
    final resolvedText = text.build(context);
    if (resolvedIcon is! Semantics || resolvedText is! RichText) {
      return _native();
    }
    final excluded = resolvedIcon.child;
    if (excluded is! ExcludeSemantics) return _native();
    final box = excluded.child;
    if (box is! SizedBox || box.width != 15 || box.height != 15) {
      return _native();
    }
    final center = box.child;
    if (center is! Center ||
        center.widthFactor != null ||
        center.heightFactor != null) {
      return _native();
    }
    final glyph = center.child;
    if (glyph is! RichText ||
        !_plain(glyph.text) ||
        !_plain(resolvedText.text) ||
        glyph.overflow != TextOverflow.visible ||
        glyph.selectionRegistrar != null ||
        resolvedText.selectionRegistrar != null ||
        (resolvedText.overflow != TextOverflow.clip &&
            resolvedText.overflow != TextOverflow.ellipsis) ||
        resolvedText.text.toPlainText().length > 4096 ||
        (resolvedText.textDirection ?? TextDirection.ltr) !=
            TextDirection.ltr ||
        MediaQuery.maybeLineHeightScaleFactorOverrideOf(context) != null ||
        MediaQuery.maybeLetterSpacingOverrideOf(context) != null ||
        MediaQuery.maybeWordSpacingOverrideOf(context) != null) {
      return _native();
    }
    final locale = Localizations.maybeLocaleOf(context);
    return _MetadataLeaf(
      glyph: _ParagraphConfiguration.from(glyph, locale),
      label: _ParagraphConfiguration.from(resolvedText, locale),
    );
  }

  static bool _plain(InlineSpan span) =>
      span.runtimeType == TextSpan &&
      span is TextSpan &&
      span.children == null &&
      span.recognizer == null &&
      span.onEnter == null &&
      span.onExit == null &&
      span.mouseCursor == MouseCursor.defer &&
      span.semanticsLabel == null &&
      span.semanticsIdentifier == null &&
      span.style?.foreground == null &&
      span.style?.background == null;
}

typedef _ParagraphSpec = ({
  InlineSpan text,
  TextAlign align,
  TextDirection direction,
  TextScaler scaler,
  bool wrap,
  TextOverflow overflow,
  int? lines,
  Locale? locale,
  StrutStyle? strut,
  TextWidthBasis widthBasis,
  TextHeightBehavior? heightBehavior,
});

extension _ParagraphConfiguration on _ParagraphSpec {
  static _ParagraphSpec from(RichText text, Locale? locale) => (
    text: text.text,
    align: text.textAlign,
    direction: text.textDirection ?? TextDirection.ltr,
    scaler: text.textScaler,
    wrap: text.softWrap,
    overflow: text.overflow,
    lines: text.maxLines,
    locale: text.locale ?? locale,
    strut: text.strutStyle,
    widthBasis: text.textWidthBasis,
    heightBehavior: text.textHeightBehavior,
  );

  TextPainter painter() => TextPainter(
    text: text,
    textAlign: align,
    textDirection: direction,
    textScaler: scaler,
    maxLines: lines,
    ellipsis: overflow == TextOverflow.ellipsis ? '…' : null,
    locale: locale,
    strutStyle: strut,
    textWidthBasis: widthBasis,
    textHeightBehavior: heightBehavior,
  );
}

class _MetadataLeaf extends LeafRenderObjectWidget {
  const _MetadataLeaf({required this.glyph, required this.label});
  final _ParagraphSpec glyph, label;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMetadataLeaf(glyph, label);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderMetadataLeaf renderObject,
  ) {
    renderObject.update(glyph, label);
  }
}

class _RenderMetadataLeaf extends RenderBox
    with RelayoutWhenSystemFontsChangeMixin, DebugOverflowIndicatorMixin {
  _RenderMetadataLeaf(this._glyph, this._label);
  _ParagraphSpec _glyph, _label;
  TextPainter? _glyphPainter, _labelPainter;
  Rect _glyphRect = Rect.zero, _labelRect = Rect.zero;
  bool _clipLabel = false;
  double _overflow = 0;

  void update(_ParagraphSpec glyph, _ParagraphSpec label) {
    if (_glyph == glyph && _label == label) return;
    _glyph = glyph;
    _label = label;
    _disposePainters();
    markNeedsLayout();
  }

  void _disposePainters() {
    _glyphPainter?.dispose();
    _labelPainter?.dispose();
    _glyphPainter = _labelPainter = null;
  }

  @override
  void systemFontsDidChange() {
    _disposePainters();
    super.systemFontsDidChange();
  }

  Size _layout(
    BoxConstraints constraints,
    TextPainter glyph,
    TextPainter label,
  ) {
    glyph.layout(
      maxWidth: _glyph.wrap || _glyph.overflow == TextOverflow.ellipsis
          ? 15
          : double.infinity,
    );
    label.layout(
      maxWidth: _label.wrap || _label.overflow == TextOverflow.ellipsis
          ? math.max(0, constraints.maxWidth - 20)
          : double.infinity,
    );
    final textSize = BoxConstraints(
      maxWidth: math.max(0, constraints.maxWidth - 20),
      maxHeight: constraints.maxHeight,
    ).constrain(label.size);
    return constraints.constrain(
      Size(
        20 + textSize.width,
        math.max(math.min(15, constraints.maxHeight), textSize.height),
      ),
    );
  }

  @override
  void performLayout() {
    final glyph = _glyphPainter ??= _glyph.painter();
    final label = _labelPainter ??= _label.painter();
    size = _layout(constraints, glyph, label);
    final glyphSize = BoxConstraints(
      maxWidth: 15,
      maxHeight: math.min(15, constraints.maxHeight),
    ).constrain(glyph.size);
    final labelSize = BoxConstraints(
      maxWidth: math.max(0, constraints.maxWidth - 20),
      maxHeight: constraints.maxHeight,
    ).constrain(label.size);
    _overflow = math.max(0, 20 + labelSize.width - size.width);
    _glyphRect =
        Offset(
          (15 - glyphSize.width) / 2,
          (size.height - glyphSize.height) / 2,
        ) &
        glyphSize;
    _labelRect = Offset(20, (size.height - labelSize.height) / 2) & labelSize;
    _clipLabel =
        labelSize.width < label.width ||
        labelSize.height < label.height ||
        label.didExceedMaxLines;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final glyph = _glyph.painter(), label = _label.painter();
    try {
      return _layout(constraints, glyph, label);
    } finally {
      glyph.dispose();
      label.dispose();
    }
  }

  double _intrinsicWidth(bool minimum) {
    final painter = _label.painter()..layout();
    try {
      return 20 +
          (minimum ? painter.minIntrinsicWidth : painter.maxIntrinsicWidth);
    } finally {
      painter.dispose();
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) => _intrinsicWidth(true);
  @override
  double computeMaxIntrinsicWidth(double height) => _intrinsicWidth(false);
  @override
  double computeMinIntrinsicHeight(double width) {
    final painter = _label.painter();
    try {
      painter.layout(
        maxWidth: _label.wrap || _label.overflow == TextOverflow.ellipsis
            ? math.max(0, width - 20)
            : double.infinity,
      );
      return math.max(15, painter.height);
    } finally {
      painter.dispose();
    }
  }

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  double computeDistanceToActualBaseline(TextBaseline baseline) => math.min(
    _glyphRect.top +
        _glyphPainter!.computeDistanceToActualBaseline(TextBaseline.alphabetic),
    _labelRect.top +
        _labelPainter!.computeDistanceToActualBaseline(TextBaseline.alphabetic),
  );

  @override
  double computeDryBaseline(BoxConstraints constraints, TextBaseline baseline) {
    final glyph = _glyph.painter(), label = _label.painter();
    try {
      final size = _layout(constraints, glyph, label);
      final glyphHeight = math.min(
        glyph.height,
        math.min(15, constraints.maxHeight),
      );
      final labelHeight = math.min(label.height, constraints.maxHeight);
      return math.min(
        (size.height - glyphHeight) / 2 +
            glyph.computeDistanceToActualBaseline(TextBaseline.alphabetic),
        (size.height - labelHeight) / 2 +
            label.computeDistanceToActualBaseline(TextBaseline.alphabetic),
      );
    } finally {
      glyph.dispose();
      label.dispose();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_overflow > precisionErrorTolerance && size.isEmpty) return;
    _glyphPainter!.paint(context.canvas, offset + _glyphRect.topLeft);
    if (_clipLabel) {
      context.canvas.save();
      context.canvas.clipRect(_labelRect.shift(offset));
    }
    _labelPainter!.paint(context.canvas, offset + _labelRect.topLeft);
    if (_clipLabel) context.canvas.restore();
    assert(() {
      if (_overflow > precisionErrorTolerance) {
        paintOverflowIndicator(
          context,
          offset,
          Offset.zero & size,
          Rect.fromLTWH(0, 0, size.width + _overflow, 0),
        );
      }
      return true;
    }());
  }

  @override
  bool hitTestSelf(Offset position) =>
      _glyphRect.contains(position) || _labelRect.contains(position);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final (rect, painter) = _labelRect.contains(position)
        ? (_labelRect, _labelPainter!)
        : (_glyphRect, _glyphPainter!);
    if (!rect.contains(position)) return false;
    final glyph = painter.getClosestGlyphForOffset(position - rect.topLeft);
    final span =
        glyph != null &&
            glyph.graphemeClusterLayoutBounds.contains(position - rect.topLeft)
        ? painter.text!.getSpanForPosition(
            TextPosition(offset: glyph.graphemeClusterCodeUnitRange.start),
          )
        : null;
    if (span case final HitTestTarget target) {
      result.add(HitTestEntry(target));
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    _disposePainters();
    super.dispose();
  }
}
