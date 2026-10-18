import 'pixel_scroll.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../tag_labels.dart';
import 'components.dart';
import 'recipe_metadata.dart';

double _textLineHeight(BuildContext context, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(text: 'Ag', style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final height = painter.height;
  painter.dispose();
  return height;
}

/// One shared extent for every grid card, derived from the rendered text styles.
double recipeGridTagHeight(BuildContext context) =>
    _textLineHeight(context, Theme.of(context).textTheme.labelSmall) + 8;

double recipeGridCardHeight(BuildContext context) {
  final theme = Theme.of(context).textTheme;
  final title = _textLineHeight(
    context,
    theme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
  );
  final description = _textLineHeight(context, theme.bodySmall);
  final text = math.max(2 * title + description, title + 2 * description) + 4;
  final tags = _textLineHeight(context, theme.labelSmall) + 8;
  return 20 + text + 8 + recipeMetadataLineHeight(context) + 8 + tags;
}

class RecipeCardTextBudget extends StatelessWidget {
  const RecipeCardTextBudget({
    super.key,
    required this.title,
    required this.description,
  });
  final String title, description;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final titleStyle = theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      );
      final painter = TextPainter(
        text: TextSpan(text: title, style: titleStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: constraints.maxWidth);
      final titleLines = painter.computeLineMetrics().length.clamp(1, 2);
      painter.dispose();
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              description,
              maxLines: 3 - titleLines,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      );
    },
  );
}

/// Add columns once another comfortably readable recipe fits.
int recipeGridColumns(double width) =>
    math.max(1, ((width + 12) / 332).floor());

/// Search takes the remaining toolbar width, capped for comfortable reading.
/// Oversized controls scroll horizontally without adding another pinned row.
class RecipeSearchToolbar extends MultiChildRenderObjectWidget {
  RecipeSearchToolbar({
    super.key,
    required Widget search,
    required Widget controls,
  }) : super(
         children: [
           search,
           PixelSingleChildScrollView(
             scrollDirection: Axis.horizontal,
             child: controls,
           ),
         ],
       );

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRecipeSearchToolbar();
}

class _RenderRecipeSearchToolbar extends RenderBox
    with
        ContainerRenderObjectMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        >,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ContainerBoxParentData<RenderBox>) {
      child.parentData = _RecipeGridParentData();
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    size = constraints.biggest;
    final search = firstChild!;
    final controls = lastChild!;
    controls.layout(
      BoxConstraints(
        maxHeight: size.height,
        maxWidth: math.max(0, size.width - 172),
      ),
      parentUsesSize: true,
    );
    final searchWidth = (size.width - controls.size.width - 12).clamp(
      160.0,
      560.0,
    );
    search.layout(
      BoxConstraints(
        maxHeight: size.height,
        minWidth: searchWidth,
        maxWidth: searchWidth,
      ),
      parentUsesSize: true,
    );
    (search.parentData! as ContainerBoxParentData<RenderBox>).offset = Offset(
      0,
      (size.height - search.size.height) / 2,
    );
    (controls.parentData! as ContainerBoxParentData<RenderBox>).offset = Offset(
      searchWidth + 12,
      (size.height - controls.size.height) / 2,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// Lazily built recipe groups measure their own tallest entry, then stretch
/// their surfaces to that height. Other rows can retain their natural height.
class RecipeGridRow extends MultiChildRenderObjectWidget {
  const RecipeGridRow({
    super.key,
    required this.columns,
    this.fixedHeight,
    required super.children,
  });

  final int columns;
  final double? fixedHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRecipeGridRow(columns, fixedHeight);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderRecipeGridRow)
      ..columns = columns
      ..fixedHeight = fixedHeight;
  }
}

class _RecipeGridParentData extends ContainerBoxParentData<RenderBox> {}

/// Cards in a row share metadata and tag slots, including empty slots.
class RecipeCardContent extends MultiChildRenderObjectWidget {
  RecipeCardContent({
    super.key,
    required Widget title,
    required Widget metadata,
    required Widget tags,
  }) : super(children: [title, metadata, tags]);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRecipeCardContent();
}

class _RenderRecipeCardContent extends RenderBox
    with
        ContainerRenderObjectMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        >,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  double metadataHeight = 0;
  double tagsHeight = 0;
  double _titleHeight = 0;
  double _metadataSlot = 0;
  double _tagsSlot = 0;

  double heightWithFooter(double metadataSlot, double tagsSlot) {
    final between = metadataSlot > 0 && tagsSlot > 0 ? 8.0 : 0.0;
    final footer = metadataSlot + between + tagsSlot;
    return _titleHeight + (footer > 0 ? 8 : 0) + footer;
  }

  void reserveFooter(double metadata, double tags) {
    if (_metadataSlot == metadata && _tagsSlot == tags) return;
    _metadataSlot = metadata;
    _tagsSlot = tags;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ContainerBoxParentData<RenderBox>) {
      child.parentData = _RecipeGridParentData();
    }
  }

  @override
  void performLayout() {
    final title = firstChild!;
    final metadata = childAfter(title)!;
    final tags = lastChild!;
    final loose = BoxConstraints.tightFor(width: constraints.maxWidth);
    title.layout(loose, parentUsesSize: true);
    metadata.layout(loose, parentUsesSize: true);
    tags.layout(loose, parentUsesSize: true);
    _titleHeight = title.size.height;
    metadataHeight = metadata.size.height;
    tagsHeight = tags.size.height;
    final metadataSlot = math.max(metadataHeight, _metadataSlot);
    final tagsSlot = math.max(tagsHeight, _tagsSlot);
    final between = metadataSlot > 0 && tagsSlot > 0 ? 8.0 : 0.0;
    final footerHeight = metadataSlot + between + tagsSlot;
    final beforeFooter = footerHeight > 0 ? 8.0 : 0.0;
    size = constraints.constrain(
      Size(
        constraints.maxWidth,
        title.size.height + beforeFooter + footerHeight,
      ),
    );
    (title.parentData! as ContainerBoxParentData<RenderBox>).offset =
        Offset.zero;
    final footerTop = size.height - footerHeight;
    (metadata.parentData! as ContainerBoxParentData<RenderBox>).offset = Offset(
      0,
      footerTop,
    );
    (tags.parentData! as ContainerBoxParentData<RenderBox>).offset = Offset(
      0,
      footerTop + metadataSlot + between,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

class _RenderRecipeGridRow extends RenderBox
    with
        ContainerRenderObjectMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        >,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  _RenderRecipeGridRow(this._columns, this._fixedHeight);

  double? _fixedHeight;
  set fixedHeight(double? value) {
    if (_fixedHeight == value) return;
    _fixedHeight = value;
    markNeedsLayout();
  }

  int _columns;
  set columns(int value) {
    // Children were stretched with tight height constraints in the last pass.
    // Re-measure after widget updates, including Cards/Compact or text changes.
    _columns = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ContainerBoxParentData<RenderBox>) {
      child.parentData = _RecipeGridParentData();
    }
  }

  double _columnWidth(double width) =>
      math.min(420, (width - 12 * (_columns - 1)) / _columns);

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    if (_fixedHeight != null) {
      return constraints.constrain(Size(constraints.maxWidth, _fixedHeight!));
    }
    final width = _columnWidth(constraints.maxWidth);
    var height = 0.0;
    var child = firstChild;
    while (child != null) {
      height = math.max(
        height,
        child.getDryLayout(BoxConstraints.tightFor(width: width)).height,
      );
      child = childAfter(child);
    }
    return constraints.constrain(Size(constraints.maxWidth, height));
  }

  @override
  void performLayout() {
    final width = _columnWidth(constraints.maxWidth);
    if (_fixedHeight != null) {
      size = constraints.constrain(Size(constraints.maxWidth, _fixedHeight!));
      var x = (size.width - (width * _columns + 12 * (_columns - 1))) / 2;
      var child = firstChild;
      while (child != null) {
        child.layout(
          BoxConstraints.tight(Size(width, size.height)),
          parentUsesSize: true,
        );
        (child.parentData! as ContainerBoxParentData<RenderBox>).offset =
            Offset(x, 0);
        x += width + 12;
        child = childAfter(child);
      }
      return;
    }
    var height = 0.0;
    final contents = <_RenderRecipeCardContent>[];
    void findContents(RenderObject object) {
      if (object is _RenderRecipeCardContent) {
        contents.add(object);
      } else {
        object.visitChildren(findContents);
      }
    }

    visitChildren(findContents);
    invokeLayoutCallback<BoxConstraints>((_) {
      for (final content in contents) {
        content.reserveFooter(0, 0);
      }
    });
    var child = firstChild;
    while (child != null) {
      child.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
      height = math.max(height, child.size.height);
      child = childAfter(child);
    }
    if (contents.isNotEmpty) {
      final metadataSlot = contents.fold(
        0.0,
        (height, content) => math.max(height, content.metadataHeight),
      );
      final tagsSlot = contents.fold(
        0.0,
        (height, content) => math.max(height, content.tagsHeight),
      );
      height = 0;
      child = firstChild;
      while (child != null) {
        // Measure text once at its final width. Footer slot differences are
        // arithmetic; only the final stretched card needs a second layout.
        var extra = 0.0;
        void footerDelta(RenderObject node) {
          if (node is _RenderRecipeCardContent) {
            extra +=
                node.heightWithFooter(metadataSlot, tagsSlot) -
                node.heightWithFooter(node.metadataHeight, node.tagsHeight);
          } else {
            node.visitChildren(footerDelta);
          }
        }

        footerDelta(child);
        height = math.max(height, child.size.height + extra);
        child = childAfter(child);
      }
      invokeLayoutCallback<BoxConstraints>((_) {
        for (final content in contents) {
          content.reserveFooter(metadataSlot, tagsSlot);
        }
      });
    }
    size = constraints.constrain(Size(constraints.maxWidth, height));
    var x = (size.width - (width * _columns + 12 * (_columns - 1))) / 2;
    child = firstChild;
    while (child != null) {
      child.layout(
        BoxConstraints.tight(Size(width, height)),
        parentUsesSize: true,
      );
      final parentData = child.parentData! as ContainerBoxParentData<RenderBox>;
      parentData.offset = Offset(x, 0);
      x += width + 12;
      child = childAfter(child);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// Static tags occupy one line; the overflow count always remains visible.
class RecipeTagLine extends StatelessWidget {
  const RecipeTagLine(this.tags, {super.key});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final values = normalizeTags(tags);
    if (values.isEmpty) return const SizedBox.shrink();
    final style = Theme.of(context).textTheme.labelSmall;
    final scaler = MediaQuery.textScalerOf(context);
    double labelWidth(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width + 16;
      painter.dispose();
      return width;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final widths = values.map(labelWidth).toList();
        var visible = values.length;
        while (visible > 0) {
          final hidden = values.length - visible;
          final occupied =
              widths.take(visible).fold(0.0, (a, b) => a + b) +
              (hidden > 0 ? labelWidth('+$hidden') : 0) +
              6 * (visible + (hidden > 0 ? 1 : 0) - 1);
          if (occupied <= constraints.maxWidth) break;
          visible--;
        }
        final hidden = values.length - visible;
        return Semantics(
          label: 'Tags: ${values.join(', ')}',
          excludeSemantics: true,
          child: Tooltip(
            message: values.join(', '),
            child: Row(
              children: [
                for (var i = 0; i < visible; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  TonalTag(values[i]),
                ],
                if (hidden > 0) ...[
                  if (visible > 0) const SizedBox(width: 6),
                  Flexible(child: TonalTag('+$hidden')),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
