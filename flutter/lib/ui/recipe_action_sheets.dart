part of 'components.dart';

class AddRecipeChoices extends StatelessWidget {
  const AddRecipeChoices({super.key});

  @override
  Widget build(BuildContext context) {
    const choices = [
      (
        'Recipe editing',
        'Write a recipe',
        'Start from scratch',
        Symbols.edit,
        false,
      ),
      (
        'Recipe import',
        'Smart Import',
        'From a link, photo, or text',
        Symbols.auto_awesome,
        true,
      ),
      (
        'Smart Create',
        'Smart Create',
        'Ideas from what you have',
        Symbols.lightbulb,
        true,
      ),
    ];
    final duration = FaceliftMotion.duration(context, MotionGroup.lists);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Add a recipe', style: FaceliftTokens.sheetTitle(context)),
        const SizedBox(height: 14),
        for (final (index, choice) in choices.indexed)
          Padding(
            padding: EdgeInsets.only(
              top: index == 0 ? 0 : FaceliftTokens.tileGap,
            ),
            child: TweenAnimationBuilder<double>(
              tween: Tween(
                begin: duration == Duration.zero ? 1.0 : 0.0,
                end: 1.0,
              ),
              duration: duration,
              curve: Interval(
                .32 * index / choices.length,
                1,
                curve: Curves.easeOutCubic,
              ),
              builder: (_, value, child) => Transform.translate(
                offset: Offset(0, 12 * (1 - value)),
                child: child,
              ),
              child: FaceliftSheetTile(
                title: choice.$2,
                subtitle: choice.$3,
                icon: choice.$4,
                accent: choice.$5,
                onTap: () => Navigator.pop(context, choice.$1),
              ),
            ),
          ),
      ],
    );
  }
}

class _RecipeActionChoices extends StatelessWidget {
  const _RecipeActionChoices({required this.recipe, required this.store});
  final RecipeSummary recipe;
  final RecipeStore store;

  Future<void> _favorite(BuildContext context) async {
    HapticFeedback.selectionClick();
    try {
      await store.toggleFavorite(recipe.id);
    } catch (_) {
      if (context.mounted) {
        showFeedback(
          context,
          'Could not update favorite.',
          kind: FeedbackKind.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final metadata = RecipeMetadata(
      servings: recipe.servings,
      totalTime: recipe.totalTime,
      prepTime: recipe.prepTime,
      cookTime: recipe.cookTime,
    );
    void choose(String action) => Navigator.pop(context, action);
    final tiles = [
      FaceliftQuickAction(
        label: 'Edit',
        icon: const Icon(Symbols.edit),
        onTap: () => choose('edit'),
      ),
      FaceliftQuickAction(
        label: 'Share',
        icon: const Icon(Symbols.share),
        onTap: () => choose('share'),
      ),
      FaceliftQuickAction(
        label: 'Add to list',
        icon: const Icon(Symbols.add_shopping_cart),
        onTap: () => choose('shopping'),
      ),
      ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final favorite =
              store.summaries
                  .where((r) => r.id == recipe.id)
                  .firstOrNull
                  ?.favorite ??
              recipe.favorite;
          return FaceliftQuickAction(
            label: favorite ? 'Favorited' : 'Favorite',
            icon: FavoriteStar(favorite: favorite, size: 24),
            accent: true,
            onTap: () => _favorite(context),
            toggled: favorite,
          );
        },
      ),
    ];
    final deleteColor = mutedDeleteColor(colors);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(recipe.title, style: FaceliftTokens.sheetTitle(context)),
        if (!metadata.isEmpty) ...[const SizedBox(height: 4), metadata],
        const SizedBox(height: 16),
        FaceliftQuickGrid(longestLabel: 'Favorited', children: tiles),
        const SizedBox(height: 12),
        Material(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(FaceliftTokens.groupRadius),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              ListTile(
                leading: Icon(
                  Symbols.check_box,
                  color: colors.onSurfaceVariant,
                ),
                title: const Text('Select'),
                onTap: () => choose('select'),
              ),
              Divider(height: 1, indent: 56, color: colors.outlineVariant),
              ListTile(
                leading: Icon(Symbols.delete, color: deleteColor),
                title: Text('Delete', style: TextStyle(color: deleteColor)),
                onTap: () => choose('delete'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
