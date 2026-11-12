import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'feedback.dart';
import 'recipe_action_motion.dart';

/// A sibling of the scroll view: visibility/fade never rebuild its slivers.
class RecipeTopButton extends StatelessWidget {
  const RecipeTopButton({
    super.key,
    required this.visible,
    required this.onPressed,
  });

  final ValueNotifier<bool> visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: feedbackVisibilityOf(context),
    builder: (context, feedback, child) => feedback
        ? const SizedBox.shrink()
        : ValueListenableBuilder(
            valueListenable: visible,
            child: child,
            builder: (context, show, child) =>
                RecipeActionMotion(visible: show, child: child!),
          ),
    child: RepaintBoundary(
      child: Semantics(
        label: 'Back to top',
        button: true,
        onTap: onPressed,
        child: ExcludeSemantics(
          child: FilledButton.tonalIcon(
            key: const Key('recipe-top-button'),
            onPressed: onPressed,
            style: ButtonStyle(
              shape: const WidgetStatePropertyAll(StadiumBorder()),
              minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 16),
              ),
              elevation: const WidgetStatePropertyAll(2),
              overlayColor: Theme.of(context).platform == TargetPlatform.android
                  ? WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.hovered) &&
                          !states.contains(WidgetState.pressed) &&
                          !states.contains(WidgetState.focused)) {
                        return Colors.transparent;
                      }
                      return null;
                    })
                  : null,
            ),
            icon: const Icon(Symbols.arrow_upward, size: 20),
            label: const Text('Top'),
          ),
        ),
      ),
    ),
  );
}
