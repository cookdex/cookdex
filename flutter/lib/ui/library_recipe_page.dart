import 'package:flutter/material.dart';

import '../app_platform.dart';
import '../cook_controller.dart';
import '../recipe_store.dart';
import 'recipe_detail.dart';
import 'window_size.dart';

/// An ordinary recipe route above Library, with its own cooking state.
class LibraryRecipePage extends StatefulWidget {
  const LibraryRecipePage({
    super.key,
    required this.store,
    required this.recipeId,
    required this.platform,
    required this.onEdit,
    required this.onActions,
    required this.onAddToShopping,
  });
  final RecipeStore store;
  final String recipeId;
  final AppPlatform platform;
  final VoidCallback onEdit;
  final ValueChanged<int> onActions, onAddToShopping;
  @override
  State<LibraryRecipePage> createState() => _LibraryRecipePageState();
}

class _LibraryRecipePageState extends State<LibraryRecipePage>
    with WidgetsBindingObserver {
  late final _cook = CookController(
    preferences: widget.store.preferences,
    setWake: widget.platform.setKeepScreenOn,
  );
  bool _resumed = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _visibility();
  }

  void _visibility() => _cook.setVisibility(
    visible: true,
    resumed: _resumed,
    obscured: ModalRoute.of(context)?.isCurrent != true,
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visibility();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cook.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: RecipeTextScale(
        factor: widget.store.preferences.recipeTextSize.factor,
        child: RecipeDetail(
          backTooltip: 'Back to Library',
          store: widget.store,
          recipeId: widget.recipeId,
          cook: _cook,
          onBack: () => Navigator.of(context).maybePop(),
          onActions: () => widget.onActions(_cook.scale),
          onEdit: widget.onEdit,
          onSource: widget.platform.openSource,
          onAddToShopping: () => widget.onAddToShopping(_cook.scale),
        ),
      ),
    ),
  );
}
