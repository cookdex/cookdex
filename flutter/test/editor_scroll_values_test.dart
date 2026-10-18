import 'package:cookdex/editor_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_test.dart'
    show controller, editor, reveal, field, enterFieldText;
import 'recipe_store_test.dart' show recipe;

void main() {
  for (final appendAfterReturn in [false, true]) {
    testWidgets(
      'scroll recycling retains draft fields; append=$appendAfterReturn',
      (tester) async {
        final (c, repo, _) = await controller(base: recipe('existing'));
        final section = c.draft.sections.first;
        section.name = 'Main';
        section.rows.addAll(
          List.generate(
            18,
            (i) => EditableIngredient(name: 'Synthetic ingredient $i'),
          ),
        );
        c.draft.steps.addAll(
          List.generate(8, (i) => EditableStep('Synthetic step $i')),
        );
        await editor(tester, c);
        final values = {
          'Title': 'Updated title',
          'Description': 'Updated description',
          'Makes': '5–6 servings',
          'Total time': '45 min',
          'Prep time': '15 min',
          'Cook time': '30 min',
        };
        for (final entry in values.entries) {
          FocusManager.instance.primaryFocus?.unfocus();
          await reveal(tester, field(entry.key));
          await enterFieldText(tester, field(entry.key), entry.value);
        }
        final row = section.rows.last;
        row.showNote = true;
        for (final entry in {
          'amount': '3/4',
          'unit': 'cup',
          'name': 'Updated ingredient',
          'note': 'freshly chopped',
        }.entries) {
          final key = find.byKey(ValueKey('${row.id}-${entry.key}'));
          FocusManager.instance.primaryFocus?.unfocus();
          await reveal(tester, key);
          await tester.tap(key);
          await tester.pumpAndSettle();
          await tester.enterText(
            find.descendant(of: key, matching: find.byType(EditableText)),
            entry.value,
          );
        }
        final step = c.draft.steps.last;
        final stepKey = find.byKey(ValueKey('${step.id}-text'));
        FocusManager.instance.primaryFocus?.unfocus();
        await reveal(tester, stepKey);
        await tester.tap(stepKey);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(of: stepKey, matching: find.byType(EditableText)),
          'Updated last step',
        );
        for (final entry in {
          'Notes': 'Updated notes',
          'Source link': 'https://example.com/updated',
        }.entries) {
          FocusManager.instance.primaryFocus?.unfocus();
          await reveal(tester, field(entry.key));
          await enterFieldText(tester, field(entry.key), entry.value);
        }
        FocusManager.instance.primaryFocus?.unfocus();
        await reveal(tester, field('Title'));
        final title = tester.widget<TextField>(field('Title')).controller!;
        if (!appendAfterReturn) {
          expect(title.text, values['Title']);
        }
        await tester.tap(field('Title'));
        await tester.pumpAndSettle();
        expect(c.draft.title, 'Updated title');
        if (appendAfterReturn) {
          await tester.enterText(field('Title'), '${title.text} plus');
          expect(c.draft.title, 'Updated title plus');
        }
        for (final entry in values.entries.skip(1)) {
          FocusManager.instance.primaryFocus?.unfocus();
          await reveal(tester, field(entry.key));
          expect(
            tester.widget<TextField>(field(entry.key)).controller!.text,
            entry.value,
          );
        }
        FocusManager.instance.primaryFocus?.unfocus();
        await reveal(tester, find.byTooltip('Section 1 options'));
        await tester.tap(find.byTooltip('Section 1 options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rename'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Main'),
          'Renamed section',
        );
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        FocusManager.instance.primaryFocus?.unfocus();
        await reveal(tester, stepKey);
        expect(
          tester
              .widget<EditableText>(
                find.descendant(
                  of: stepKey,
                  matching: find.byType(EditableText),
                ),
              )
              .controller
              .text,
          'Updated last step',
        );
        for (final entry in {
          'Notes': 'Updated notes',
          'Source link': 'https://example.com/updated',
        }.entries) {
          FocusManager.instance.primaryFocus?.unfocus();
          await reveal(tester, field(entry.key));
          expect(
            tester.widget<TextField>(field(entry.key)).controller!.text,
            entry.value,
          );
        }
        FocusManager.instance.primaryFocus?.unfocus();
        await reveal(tester, find.byKey(ValueKey('${row.id}-name')));
        for (final entry in {
          'amount': '3/4',
          'unit': 'cup',
          'name': 'Updated ingredient',
          'note': 'freshly chopped',
        }.entries) {
          final key = find.byKey(ValueKey('${row.id}-${entry.key}'));
          expect(
            tester
                .widget<EditableText>(
                  find.descendant(of: key, matching: find.byType(EditableText)),
                )
                .controller
                .text,
            entry.value,
          );
        }
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        final stored = repo.recipes['existing']!.fields;
        expect(
          stored.title,
          appendAfterReturn ? 'Updated title plus' : 'Updated title',
        );
        expect(stored.description, values['Description']);
        expect(stored.servings, values['Makes']);
        expect(stored.totalTime, values['Total time']);
        expect(stored.prepTime, values['Prep time']);
        expect(stored.cookTime, values['Cook time']);
        expect(stored.notes, 'Updated notes');
        expect(stored.source, 'https://example.com/updated');
        expect(stored.ingredients.last.name, 'Updated ingredient');
        expect(stored.ingredients.last.unit, 'cup');
        expect(stored.ingredients.last.prepNote, 'freshly chopped');
        expect(stored.ingredients.last.section, 'Renamed section');
        expect(repo.inputs!.last, '3/4');
        expect(stored.steps.last, 'Updated last step');
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      },
    );
  }
}
