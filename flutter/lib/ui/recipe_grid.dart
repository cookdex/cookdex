import 'pixel_scroll.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../tag_labels.dart';
import 'components.dart';
import 'recipe_metadata.dart';

double recipeGridColumnWidth(double width, int columns) =>
    math.min(420, (width - 12 * (columns - 1)) / columns);

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
    this.preparedTitle,
    this.preparedTitleLines,
  });
  final String title, description;
  final Widget? preparedTitle;
  final int? preparedTitleLines;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final titleStyle = theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      );
      final painter = preparedTitle == null
          ? TextPainter(
              text: TextSpan(text: title, style: titleStyle),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
              maxLines: 2,
              ellipsis: '…',
            )
          : null;
      painter?.layout(maxWidth: constraints.maxWidth);
      final titleLines =
          preparedTitleLines ??
          painter!.computeLineMetrics().length.clamp(1, 2);
      painter?.dispose();
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          preparedTitle ??
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

  double _columnWidth(double width) => recipeGridColumnWidth(width, _columns);

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
  const RecipeTagLine(
    this.tags, {
    super.key,
    this.preparedValues,
    this.preparedVisible,
    this.preparedWidth,
  });
  final List<String>? preparedValues;
  final int? preparedVisible;
  final double? preparedWidth;

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final values = preparedValues ?? normalizeTags(tags);
    if (values.isEmpty) return const SizedBox.shrink();
    final style = Theme.of(context).textTheme.labelSmall;
    final scaler = MediaQuery.textScalerOf(context);
    final inherited = DefaultTextStyle.of(context);
    final paintedStyle = inherited.style.merge(
      style?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
    final locale = Localizations.maybeLocaleOf(context);
    // The original fit measurement deliberately uses the theme style, while
    // Text also applies inherited/accessibility overrides. Keep that original
    // path whenever the two have different metrics or nonstandard behavior.
    final sameMetrics =
        style != null &&
        style
                .copyWith(inherit: false)
                .compareTo(paintedStyle.copyWith(inherit: false))
                .index <=
            RenderComparison.paint.index;
    if (sameMetrics &&
        Directionality.of(context) == TextDirection.ltr &&
        !MediaQuery.boldTextOf(context) &&
        MediaQuery.maybeLineHeightScaleFactorOverrideOf(context) == null &&
        MediaQuery.maybeLetterSpacingOverrideOf(context) == null &&
        MediaQuery.maybeWordSpacingOverrideOf(context) == null &&
        SelectionContainer.maybeOf(context) == null &&
        (locale == null || locale.languageCode == 'en') &&
        (inherited.textAlign == null ||
            inherited.textAlign == TextAlign.start) &&
        inherited.softWrap &&
        inherited.maxLines == null &&
        inherited.overflow == TextOverflow.clip &&
        paintedStyle.overflow == null &&
        inherited.textWidthBasis == TextWidthBasis.parent &&
        inherited.textHeightBehavior == null &&
        DefaultTextHeightBehavior.maybeOf(context) == null) {
      return Semantics(
        label: 'Tags: ${values.join(', ')}',
        excludeSemantics: true,
        child: Tooltip(
          message: values.join(', '),
          child: _PaintedRecipeTags(
            values,
            style: paintedStyle,
            scaler: scaler,
            direction: Directionality.of(context),
            locale: locale,
            background: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
      );
    }
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
        final prepared =
            preparedVisible != null &&
            preparedWidth == constraints.maxWidth &&
            values.every((value) => !value.contains('\n'));
        final widths = prepared
            ? const <double>[]
            : values.map(labelWidth).toList();
        var visible = prepared ? preparedVisible! : values.length;
        while (!prepared && visible > 0) {
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

/// Owns each shaped label for both fitting and painting. There is no cache
/// shared by recipes, and labels beyond the first non-fitting one are unshaped.
class _PaintedRecipeTags extends LeafRenderObjectWidget {
  const _PaintedRecipeTags(
    this.values, {
    required this.style,
    required this.scaler,
    required this.direction,
    required this.locale,
    required this.background,
  });

  final List<String> values;
  final TextStyle style;
  final TextScaler scaler;
  final TextDirection direction;
  final Locale? locale;
  final Color background;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderRecipeTags(
    _TagParagraphs(values, style, scaler, direction, locale),
    background,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRecipeTags renderObject,
  ) {
    renderObject.update(values, style, scaler, direction, locale, background);
  }
}

class _RenderRecipeTags extends RenderBox
    with RelayoutWhenSystemFontsChangeMixin {
  _RenderRecipeTags(this.paragraphs, this.background);

  _TagParagraphs paragraphs;
  Color background;

  void update(
    List<String> values,
    TextStyle style,
    TextScaler scaler,
    TextDirection direction,
    Locale? locale,
    Color background,
  ) {
    if (!listEquals(values, paragraphs.values) ||
        style != paragraphs.style ||
        scaler != paragraphs.scaler ||
        direction != paragraphs.direction ||
        locale != paragraphs.locale) {
      paragraphs.dispose();
      paragraphs = _TagParagraphs(values, style, scaler, direction, locale);
      markNeedsLayout();
    }
    if (this.background != background) {
      this.background = background;
      markNeedsPaint();
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final dry = _TagParagraphs(
      paragraphs.values,
      paragraphs.style,
      paragraphs.scaler,
      paragraphs.direction,
      paragraphs.locale,
    );
    try {
      return dry.layout(constraints);
    } finally {
      dry.dispose();
    }
  }

  @override
  void performLayout() => size = paragraphs.layout(constraints);

  @override
  bool hitTestSelf(Offset position) => paragraphs.hitTest(position, size);

  @override
  void paint(PaintingContext context, Offset offset) =>
      paragraphs.paint(context.canvas, offset, size, background);

  @override
  void systemFontsDidChange() {
    super.systemFontsDidChange();
    paragraphs.invalidateFonts();
  }

  @override
  void dispose() {
    paragraphs.dispose();
    super.dispose();
  }
}

class _TagParagraphs {
  _TagParagraphs(
    this.values,
    this.style,
    this.scaler,
    this.direction,
    this.locale,
  ) : labels = List.filled(values.length, null);

  final List<String> values;
  final TextStyle style;
  final TextScaler scaler;
  final TextDirection direction;
  final Locale? locale;
  final List<TextPainter?> labels;
  TextPainter? counter;
  int visible = 0;
  final List<Size> boxes = [];

  TextPainter _paragraph(String text) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: direction,
    textScaler: scaler,
    locale: locale,
  );

  TextPainter _label(int index) {
    final painter = labels[index] ??= _paragraph(values[index]);
    painter.layout();
    return painter;
  }

  Size layout(BoxConstraints constraints) {
    var occupied = 0.0;
    visible = 0;
    boxes.clear();
    while (visible < values.length) {
      final width = _label(visible).width + 16;
      final next = occupied + (visible > 0 ? 6 : 0) + width;
      if (next > constraints.maxWidth) break;
      occupied = next;
      visible++;
    }
    if (visible < values.length) {
      counter ??= _paragraph('');
      while (true) {
        counter!.text = TextSpan(
          text: '+${values.length - visible}',
          style: style,
        );
        counter!.layout();
        final next = occupied + (visible > 0 ? 6 : 0) + counter!.width + 16;
        if (next <= constraints.maxWidth || visible == 0) break;
        visible--;
        occupied -= labels[visible]!.width + 16 + (visible > 0 ? 6 : 0);
      }
    }
    var height = 0.0;
    for (var i = 0; i < visible; i++) {
      final box = Size(
        labels[i]!.width + 16,
        math.min(constraints.maxHeight, labels[i]!.height + 8),
      );
      boxes.add(box);
      height = math.max(height, box.height);
    }
    if (visible < values.length) {
      final remaining = math.max(
        0.0,
        constraints.maxWidth - occupied - (visible > 0 ? 6 : 0),
      );
      counter!.layout(maxWidth: math.max(0, remaining - 16));
      final box = Size(
        math.min(remaining, counter!.width + 16),
        math.min(constraints.maxHeight, counter!.height + 8),
      );
      boxes.add(box);
      height = math.max(height, box.height);
      occupied += (visible > 0 ? 6 : 0) + box.width;
    }
    return constraints.constrain(
      Size(
        constraints.hasBoundedWidth ? constraints.maxWidth : occupied,
        height,
      ),
    );
  }

  bool hitTest(Offset position, Size size) {
    var x = 0.0;
    for (final box in boxes) {
      final rect = Offset(x, (size.height - box.height) / 2) & box;
      if (RRect.fromRectAndRadius(
        rect,
        const Radius.circular(4),
      ).contains(position)) {
        return true;
      }
      x += box.width + 6;
    }
    return false;
  }

  void invalidateFonts() {
    for (final painter in labels) {
      painter?.markNeedsLayout();
    }
    counter?.markNeedsLayout();
  }

  void paint(Canvas canvas, Offset offset, Size size, Color background) {
    final paint = Paint()..color = background;
    var x = 0.0;
    for (var i = 0; i < boxes.length; i++) {
      final box = boxes[i];
      final origin = offset + Offset(x, (size.height - box.height) / 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(origin & box, const Radius.circular(4)),
        paint,
      );
      final text = i < visible ? labels[i]! : counter!;
      final textOrigin = origin + const Offset(8, 4);
      final textBox = Size(
        math.max(0, box.width - 16),
        math.max(0, box.height - 8),
      );
      final clip = text.width > textBox.width || text.height > textBox.height;
      if (clip) {
        canvas.save();
        canvas.clipRect(textOrigin & textBox);
      }
      text.paint(canvas, textOrigin);
      if (clip) canvas.restore();
      x += box.width + 6;
    }
  }

  void dispose() {
    for (final painter in labels) {
      painter?.dispose();
    }
    counter?.dispose();
  }
}
