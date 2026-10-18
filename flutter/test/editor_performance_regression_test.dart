import 'package:cookdex/draft_storage.dart';
import 'package:cookdex/editor_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_test.dart' show controller, editor, field, enterFieldText;

class CountingDrafts extends MemoryDraftStorage {
  int writes = 0;
  @override
  Future<void> write(Map<String, dynamic> value) {
    writes++;
    return super.write(value);
  }
}

void main() {
  testWidgets(
    'typing coalesces draft snapshots and flush preserves final input',
    (tester) async {
      final storage = CountingDrafts();
      final (c, _, _) = await controller(storage: storage);
      await editor(tester, c);
      for (var i = 0; i < 20; i++) {
        await enterFieldText(tester, field('Title'), 'Recipe $i');
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(storage.writes, 0);
      await tester.pump(const Duration(milliseconds: 450));
      expect(storage.writes, 1);
      await enterFieldText(tester, field('Title'), 'Final title');
      await c.flush();
      expect(storage.writes, 2);
      expect((await storage.read())!['title'], 'Final title');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'large editor builds a viewport of rows and typing leaves rows alone',
    (tester) async {
      final (c, _, _) = await controller();
      c.draft.sections.first.rows
        ..clear()
        ..addAll(
          List.generate(80, (i) => EditableIngredient(name: 'Ingredient $i')),
        );
      c.draft.steps
        ..clear()
        ..addAll(List.generate(50, (i) => EditableStep('Step $i')));
      await editor(tester, c);
      final ids = {
        ...c.draft.sections.first.rows.map((r) => r.id),
        ...c.draft.steps.map((s) => s.id),
      };
      final mounted = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            ids.contains((w.key as ValueKey<String>).value),
      );
      expect(mounted.evaluate().length, lessThan(15));
      var rebuilt = 0;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        final key = element.widget.key;
        if (builtOnce &&
            key is ValueKey<String> &&
            ids.any((id) => key.value.startsWith(id))) {
          rebuilt++;
        }
      };
      await enterFieldText(tester, field('Title'), 'New title');
      await tester.pump();
      debugOnRebuildDirtyWidget = null;
      expect(rebuilt, 0);
      await c.flush();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
