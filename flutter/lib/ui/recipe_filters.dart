import 'package:flutter/material.dart';

import '../local_preferences.dart';
import 'components.dart';

Future<void> showRecipeSearchFields(
  BuildContext context,
  LocalPreferences preferences,
) => showCookdexSheet<void>(
  context,
  child: StatefulBuilder(
    builder: (context, update) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Search in',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        for (final field in SearchField.values)
          CheckboxListTile(
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
        TextButton(
          onPressed: () {
            preferences.resetSearch();
            update(() {});
          },
          child: const Text('Reset'),
        ),
      ],
    ),
  ),
);
