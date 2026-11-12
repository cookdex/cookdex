import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'facelift_tokens.dart';

class _SheetIcon extends StatelessWidget {
  const _SheetIcon({
    required this.child,
    required this.accent,
    this.quick = false,
  });
  final Widget child;
  final bool accent, quick;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final size = quick
        ? FaceliftTokens.quickIconSize
        : FaceliftTokens.sheetIconSize;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent ? colors.tertiaryContainer : colors.primaryContainer,
        borderRadius: BorderRadius.circular(
          quick
              ? FaceliftTokens.quickIconRadius
              : FaceliftTokens.sheetIconRadius,
        ),
      ),
      child: IconTheme.merge(
        data: IconThemeData(
          size: quick ? 24 : 28,
          color: accent
              ? colors.onTertiaryContainer
              : colors.onPrimaryContainer,
        ),
        child: child,
      ),
    );
  }
}

class FaceliftSheetTile extends StatelessWidget {
  const FaceliftSheetTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.onTap,
    this.accent = false,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(FaceliftTokens.groupRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              _SheetIcon(accent: accent, child: Icon(icon)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: FaceliftTokens.tileTitle(context)),
                    if (subtitle case final detail?) ...[
                      const SizedBox(height: 2),
                      Text(detail, style: FaceliftTokens.tileSubtitle(context)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Symbols.chevron_right, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class FaceliftQuickAction extends StatelessWidget {
  const FaceliftQuickAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.accent = false,
    this.toggled,
  });
  final String label;
  final Widget icon;
  final VoidCallback onTap;
  final bool accent;
  final bool? toggled;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    toggled: toggled,
    child: Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(FaceliftTokens.groupRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          child: Column(
            children: [
              _SheetIcon(accent: accent, quick: true, child: icon),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: FaceliftTokens.quickLabel(context),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Keep quick actions in one reading order at enlarged text sizes.
class FaceliftQuickGrid extends StatelessWidget {
  const FaceliftQuickGrid({
    super.key,
    required this.children,
    required this.longestLabel,
  });
  final List<Widget> children;
  final String longestLabel;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final label = TextPainter(
      text: TextSpan(
        text: longestLabel,
        style: FaceliftTokens.quickLabel(context),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final minWidth =
        label.width.ceilToDouble().clamp(
          FaceliftTokens.quickIconSize,
          double.infinity,
        ) +
        8;
    label.dispose();
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final fits =
            children.length * minWidth + (children.length - 1) * gap <=
            constraints.maxWidth;
        final columns = fits ? children.length : 2.clamp(1, children.length);
        return Column(
          children: [
            for (int start = 0; start < children.length; start += columns) ...[
              if (start > 0) const SizedBox(height: gap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (
                      var i = start;
                      i < start + columns && i < children.length;
                      i++
                    ) ...[
                      if (i > start) const SizedBox(width: gap),
                      Expanded(child: children[i]),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
