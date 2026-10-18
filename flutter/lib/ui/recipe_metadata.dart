import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../yield_presentation.dart';

/// Reserved metadata row height follows the user's text scaling and theme.
double recipeMetadataLineHeight(BuildContext context) {
  final style = Theme.of(context).textTheme.bodySmall;
  final textHeight =
      MediaQuery.textScalerOf(context).scale(style?.fontSize ?? 12) *
      (style?.height ?? 1);
  return textHeight < 15 ? 15 : textHeight;
}

/// Present yields without changing stored text and distinguish time fields.
class RecipeMetadata extends StatelessWidget {
  const RecipeMetadata({
    super.key,
    required this.servings,
    required this.totalTime,
    required this.prepTime,
    required this.cookTime,
    this.showAllTimes = false,
    this.singleLine = false,
  });

  final String servings;
  final String totalTime;
  final String prepTime;
  final String cookTime;
  final bool showAllTimes;
  final bool singleLine;

  bool get isEmpty =>
      servings.isEmpty &&
      totalTime.isEmpty &&
      prepTime.isEmpty &&
      cookTime.isEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final yieldInfo = presentRecipeYield(servings);
    Widget item(IconData icon, String text, String label, {String? prefix}) =>
        Semantics(
          label: '$label: $text',
          excludeSemantics: true,
          child: Tooltip(
            message: '$label: $text',
            excludeFromSemantics: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    prefix == null ? text : '$prefix $text',
                    style: theme.textTheme.bodySmall,
                    maxLines: singleLine ? 1 : null,
                    overflow: singleLine ? TextOverflow.ellipsis : null,
                    softWrap: !singleLine,
                  ),
                ),
              ],
            ),
          ),
        );
    final items = <Widget>[
      if (yieldInfo.text.isNotEmpty)
        item(
          yieldInfo.isServings ? Symbols.group : Symbols.inventory_2,
          yieldInfo.text,
          yieldInfo.isServings ? 'Servings' : 'Yield',
        ),
      if (showAllTimes || totalTime.isEmpty) ...[
        if (prepTime.isNotEmpty)
          item(Symbols.schedule, prepTime, 'Prep time', prefix: 'Prep'),
        if (cookTime.isNotEmpty)
          item(Symbols.schedule, cookTime, 'Cook time', prefix: 'Cook'),
      ],
      if (totalTime.isNotEmpty)
        item(
          Symbols.schedule,
          totalTime,
          'Total time',
          prefix: showAllTimes && (prepTime.isNotEmpty || cookTime.isNotEmpty)
              ? 'Total'
              : null,
        ),
    ];
    if (singleLine) {
      return SizedBox(
        height: recipeMetadataLineHeight(context),
        child: Row(
          children: [
            for (final (index, child) in items.indexed) ...[
              if (index > 0) const SizedBox(width: 14),
              Flexible(child: child),
            ],
          ],
        ),
      );
    }
    return Wrap(spacing: 14, runSpacing: 4, children: items);
  }
}
