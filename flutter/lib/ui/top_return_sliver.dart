import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Ordinary SliverList behavior, with an explicit origin for a Top-only skip.
class TopReturnSliverList extends SliverList {
  TopReturnSliverList.builder({
    super.key,
    required super.itemBuilder,
    super.itemCount,
    super.findChildIndexCallback,
  }) : super.builder();

  @override
  RenderTopReturnSliverList createRenderObject(BuildContext context) =>
      RenderTopReturnSliverList(
        childManager: context as SliverMultiBoxAdaptorElement,
      );
}

class RenderTopReturnSliverList extends RenderSliverList {
  RenderTopReturnSliverList({required super.childManager});

  bool _restartAtTop = false;

  void restartAtTop() {
    _restartAtTop = true;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    if (_restartAtTop) {
      _restartAtTop = false;
      // A variable-height sliver normally walks backward from its first live
      // child. At a deep Top skip that lays out the entire hidden middle. Start
      // from index zero instead; the existing keep-alive budget still applies.
      collectGarbage(childCount, 0);
    }
    super.performLayout();
  }
}
