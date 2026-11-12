import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:material_symbols_icons/symbols.dart';

import '../local_preferences.dart';
import 'components.dart';
import 'facelift_tokens.dart';

Future<void> showRecipeSearchFields(
  BuildContext context,
  LocalPreferences preferences,
) => showCookdexSheet<void>(
  context,
  useRootNavigator: true,
  backgroundColor: Theme.of(context).colorScheme.surface,
  child: StatefulBuilder(
    builder: (context, update) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Search in',
                style: FaceliftTokens.sheetTitle(context),
              ),
            ),
            if (!setEquals(
              preferences.searchFields,
              LocalPreferences.defaultSearchFields,
            ))
              FilledButton.tonal(
                onPressed: () {
                  preferences.setSearchFields(
                    Set.of(LocalPreferences.defaultSearchFields),
                  );
                  update(() {});
                },
                child: const Text('Reset'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Choose which parts of a recipe to search.',
          style: FaceliftTokens.tileSubtitle(context),
        ),
        const SizedBox(height: 12),
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(FaceliftTokens.groupRadius),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final field in SearchField.values) ...[
                if (field != SearchField.values.first)
                  const Divider(height: 1, indent: 60, endIndent: 16),
                CheckboxListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  secondary: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      switch (field) {
                        SearchField.title => Symbols.title,
                        SearchField.ingredients => Symbols.format_list_bulleted,
                        SearchField.tags => Symbols.sell,
                        SearchField.notes => Symbols.notes,
                        SearchField.description => Symbols.subject,
                      },
                      size: 20,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  title: Text(switch (field) {
                    SearchField.title => 'Title',
                    SearchField.ingredients => 'Ingredients',
                    SearchField.tags => 'Tags',
                    SearchField.notes => 'Notes',
                    SearchField.description => 'Description',
                  }),
                  value: preferences.searchFields.contains(field),
                  onChanged: (checked) {
                    final fields = {...preferences.searchFields};
                    checked! ? fields.add(field) : fields.remove(field);
                    preferences.setSearchFields(fields);
                    update(() {});
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  ),
);
