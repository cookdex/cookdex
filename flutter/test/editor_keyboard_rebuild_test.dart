import 'package:cookdex/editor_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_test.dart' show controller, editor;

void main() {
  testWidgets('IME animation does not rebuild ingredient and step fields', (
    tester,
  ) async {
    final (c, _, _) = await controller();
    c.draft.sections.first.rows
      ..clear()
      ..addAll(
        List.generate(30, (i) => EditableIngredient(name: 'Ingredient $i')),
      );
    c.draft.steps
      ..clear()
      ..addAll(List.generate(20, (i) => EditableStep('Instruction $i')));
    await editor(tester, c);
    final ids = {
      ...c.draft.sections.first.rows.map((r) => r.id),
      ...c.draft.steps.map((r) => r.id),
    };
    var rowBuilds = 0;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      final key = element.widget.key;
      if (builtOnce &&
          element.widget.runtimeType.toString() == '_EditorField' &&
          key is ValueKey<String> &&
          ids.any((id) => key.value.startsWith(id))) {
        rowBuilds++;
      }
    };
    addTearDown(() {
      debugOnRebuildDirtyWidget = null;
      tester.view.resetViewInsets();
    });
    for (final inset in [
      ...List.generate(16, (i) => (i + 1) * 16.0),
      ...List.generate(16, (i) => (15 - i) * 16.0),
    ]) {
      tester.view.viewInsets = FakeViewPadding(bottom: inset);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      rowBuilds,
      0,
      reason:
          'Only the keyboard suggestion strip should observe inset animation.',
    );
  });
}
