import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../recipe_store.dart';
import 'facelift_motion.dart';

class AppNavigation extends StatelessWidget {
  const AppNavigation({
    super.key,
    required this.store,
    required this.selected,
    required this.onSelect,
    this.rail = false,
    this.cooking = false,
  });

  final RecipeStore store;
  final int selected;
  final ValueChanged<int> onSelect;
  final bool rail, cooking;

  @override
  Widget build(BuildContext context) {
    final destinations = [
      (
        'Recipes',
        const Icon(Symbols.menu_book),
        const Icon(Symbols.menu_book, fill: 1),
      ),
      (
        'Shopping list',
        _ShoppingBadge(store: store),
        _ShoppingBadge(store: store, selected: true),
      ),
      (
        'Settings',
        const Icon(Symbols.settings),
        const Icon(Symbols.settings, fill: 1),
      ),
    ];
    if (rail) {
      return NavigationRail(
        scrollable: true,
        selectedIndex: selected,
        onDestinationSelected: onSelect,
        groupAlignment: 0,
        labelType: NavigationRailLabelType.all,
        destinations: [
          for (final (label, icon, selectedIcon) in destinations)
            NavigationRailDestination(
              icon: icon,
              selectedIcon: selectedIcon,
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(label, textAlign: TextAlign.center),
              ),
            ),
        ],
      );
    }
    return _CookingBarVisibility(
      visible: !cooking,
      child: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: onSelect,
        animationDuration: FaceliftMotion.duration(
          context,
          MotionGroup.floating,
        ),
        destinations: [
          for (final (label, icon, selectedIcon) in destinations)
            NavigationDestination(
              icon: icon,
              selectedIcon: selectedIcon,
              label: label,
            ),
        ],
      ),
    );
  }
}

class _ShoppingBadge extends StatelessWidget {
  const _ShoppingBadge({required this.store, this.selected = false});

  final RecipeStore store;
  final bool selected;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: store.shoppingCount,
    builder: (context, count, child) =>
        Badge(isLabelVisible: count > 0, label: Text('$count'), child: child),
    child: Icon(Symbols.shopping_cart, fill: selected ? 1 : 0),
  );
}

class _CookingBarVisibility extends StatelessWidget {
  const _CookingBarVisibility({required this.visible, required this.child});
  final bool visible;
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    duration: FaceliftMotion.duration(context, MotionGroup.cookEntry),
    tween: Tween(end: visible ? 0 : 1),
    child: child,
    builder: (context, cooking, bar) {
      final value = 1 - Easing.emphasizedDecelerate.transform(cooking);
      if (value == 0) return const SizedBox.shrink();
      return ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: value,
          child: IgnorePointer(
            ignoring: !visible,
            child: FractionalTranslation(
              translation: Offset(0, 1 - value),
              child: bar,
            ),
          ),
        ),
      );
    },
  );
}
