import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The Library's fixed-size favorite control. InkResponse keeps standard input,
/// focus, feedback and semantics without resolving a general ButtonStyle tree.
class RecipeFavoriteButton extends StatelessWidget {
  const RecipeFavoriteButton({
    super.key,
    required this.title,
    required this.favorite,
    required this.onPressed,
    this.focusNode,
  });

  final String title;
  final bool favorite;
  final VoidCallback onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      container: true,
      button: true,
      enabled: true,
      child: SizedBox.square(
        dimension: 48,
        child: Tooltip(
          message: '${favorite ? 'Unfavorite' : 'Favorite'} $title',
          child: InkResponse(
            onTap: onPressed,
            focusNode: focusNode,
            containedInkWell: true,
            highlightShape: BoxShape.rectangle,
            customBorder: const StadiumBorder(),
            highlightColor: Colors.transparent,
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return colors.onSurfaceVariant.withValues(alpha: .1);
              }
              if (states.contains(WidgetState.hovered)) {
                return colors.onSurfaceVariant.withValues(alpha: .08);
              }
              if (states.contains(WidgetState.focused)) {
                return colors.onSurfaceVariant.withValues(alpha: .1);
              }
              return Colors.transparent;
            }),
            splashFactory: theme.splashFactory,
            enableFeedback: true,
            child: Center(
              child: Icon(
                Symbols.star,
                size: 24,
                fill: favorite ? 1 : 0,
                color: favorite ? colors.tertiary : colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
