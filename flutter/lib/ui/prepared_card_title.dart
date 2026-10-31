import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A laid-out title owned jointly by its bounded cache and mounted render boxes.
/// The supplied painter must have been laid out with minWidth zero and [maxWidth].
class PreparedTitle {
  PreparedTitle(this.painter, {required this.maxWidth});

  final TextPainter painter;
  final double maxWidth;
  int _leases = 0;
  bool _cacheOwned = true;
  bool _disposed = false;

  void _retain() {
    assert(!_disposed);
    _leases++;
  }

  void _release() {
    assert(_leases > 0);
    _leases--;
    _disposeIfUnused();
  }

  /// Eviction does not invalidate a title still displayed by a mounted card.
  void releaseCache() {
    _cacheOwned = false;
    _disposeIfUnused();
  }

  void _disposeIfUnused() {
    if (!_cacheOwned && _leases == 0 && !_disposed) {
      _disposed = true;
      painter.dispose();
    }
  }
}

/// Text-compatible discovery with painting supplied by the prepared paragraph.
/// Its caller resolves all inherited text settings before preparing the title.
class PreparedCardTitle extends Text {
  const PreparedCardTitle(super.data, {super.key, required this.prepared});

  final PreparedTitle prepared;

  @override
  Widget build(BuildContext context) => _PreparedTitleLeaf(prepared, data!);
}

class _PreparedTitleLeaf extends LeafRenderObjectWidget {
  const _PreparedTitleLeaf(this.prepared, this.label);
  final PreparedTitle prepared;
  final String label;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPreparedTitle(prepared, label);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPreparedTitle renderObject,
  ) {
    renderObject.update(prepared, label);
  }
}

class _RenderPreparedTitle extends RenderBox {
  _RenderPreparedTitle(this._prepared, this._label) {
    _prepared._retain();
  }

  PreparedTitle _prepared;
  String _label;
  TextPainter? _fallback;
  TextPainter get _painter => _fallback ?? _prepared.painter;

  void update(PreparedTitle prepared, String label) {
    if (!identical(prepared, _prepared)) {
      prepared._retain();
      _prepared._release();
      _prepared = prepared;
      _fallback?.dispose();
      _fallback = null;
      markNeedsLayout();
      markNeedsPaint();
    }
    _label = label;
    markNeedsSemanticsUpdate();
  }

  TextPainter _copyPainter() {
    final source = _prepared.painter;
    return TextPainter(
      text: source.text,
      textAlign: source.textAlign,
      textDirection: source.textDirection,
      textScaler: source.textScaler,
      maxLines: source.maxLines,
      ellipsis: source.ellipsis,
      locale: source.locale,
      strutStyle: source.strutStyle,
      textWidthBasis: source.textWidthBasis,
      textHeightBehavior: source.textHeightBehavior,
    );
  }

  @override
  void performLayout() {
    if (constraints.minWidth == 0 &&
        constraints.maxWidth == _prepared.maxWidth) {
      _fallback?.dispose();
      _fallback = null;
    } else {
      (_fallback ??= _copyPainter()).layout(
        minWidth: constraints.minWidth,
        maxWidth: constraints.maxWidth,
      );
    }
    size = constraints.constrain(_painter.size);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    if (constraints.minWidth == 0 &&
        constraints.maxWidth == _prepared.maxWidth) {
      return constraints.constrain(_prepared.painter.size);
    }
    final painter = _copyPainter()
      ..layout(minWidth: constraints.minWidth, maxWidth: constraints.maxWidth);
    final result = constraints.constrain(painter.size);
    painter.dispose();
    return result;
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _prepared.painter.minIntrinsicWidth;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _prepared.painter.maxIntrinsicWidth;

  @override
  double computeMinIntrinsicHeight(double width) =>
      computeDryLayout(BoxConstraints(maxWidth: width)).height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  double computeDistanceToActualBaseline(TextBaseline baseline) =>
      _painter.computeDistanceToActualBaseline(baseline);

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_painter.width > size.width || _painter.height > size.height) {
      context.pushClipRect(
        needsCompositing,
        offset,
        Offset.zero & size,
        (context, offset) => _painter.paint(context.canvas, offset),
      );
    } else {
      _painter.paint(context.canvas, offset);
    }
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..label = _label
      ..textDirection = _prepared.painter.textDirection;
  }

  @override
  void dispose() {
    _fallback?.dispose();
    _prepared._release();
    super.dispose();
  }
}
