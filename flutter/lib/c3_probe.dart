// Disposable acceptance harness, no production paths or provider calls.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'bridge_loader.dart';
import 'src/rust/api.dart';

void check(bool value, String name) {
  if (!value) throw StateError('C3 probe failed: $name');
}

Future<void> expectCode(Future<Object?> action, ErrorCode code) async {
  try {
    await action;
  } on ServiceError catch (error) {
    check(error.code == code, 'typed error $code');
    return;
  }
  throw StateError('Expected $code');
}

Future<void> verifyC3() async {
  await initializeBridge();
  final root = await Directory.systemTemp.createTemp('cookdex-c3-');
  var session = await CoreSession.open(privateRoot: root.path);
  final streamToken = Operation();
  final events = StreamIterator(
    subscribe(session: session, operation: streamToken),
  );
  try {
    check(await events.moveNext(), 'initial snapshot');
    check(events.current is CollectionEvent_Snapshot, 'snapshot handshake');
    final candidates = await parseText(
      text:
          '''Recipe Book Text v1
Title: C3 synthetic soup
Description: Unicode é | metadata
Servings: 2
Prep time: 5 min
Cook time: 10 min
Total time: 15 min
Source: https://example.com/soup
Tags: ["fixture"]

Ingredients (amount | unit | name | prep note | optional):
Section: Sauce
- 33/100 | cup | cream | stir | yes
- to taste |  | salt |  | no
-  |  | parsley |  | no
- 1 1/2–2 | cup | water |  | no

Steps:
1. Stir.

Notes: Synthetic only.
--- End recipe ---'''
              .replaceFirst('Unicode é | metadata', r'Unicode é \| metadata'),
    );
    check(candidates.candidates.length == 1, 'one typed candidate');
    final fields = candidates.candidates.single.recipe.fields;
    final token = Operation();
    var snapshot = await session.importOne(
      generation: 0,
      fields: fields,
      operation: token,
    );
    check(!token.cancel(), 'late cancellation reconciles committed write');
    check(await events.moveNext(), 'commit notification');
    final change = (events.current as CollectionEvent_Change).field0;
    check(
      change.generation == snapshot.generation && change.changed.length == 1,
      'generation and changed ID',
    );
    check(snapshot.setAsideCount == 0, 'typed set-aside count');
    final backupReport = await session.backupReport(operation: Operation());
    check(
      backupReport.omitted == 0 && backupReport.bytes.isNotEmpty,
      'typed backup omission report',
    );
    final noDiscard = await session.discardSetAside(
      generation: snapshot.generation,
      operation: Operation(),
    );
    check(
      noDiscard.generation == snapshot.generation &&
          noDiscard.setAsideCount == 0,
      'discard does not change a healthy collection',
    );
    final id = snapshot.summaries.single.id;
    final recipe = (await session.detail(id: id))!;
    check(
      recipe.fields.ingredients[0].amount ==
          const Amount.rational(numerator: 33, denominator: 100),
      'canonical no snap',
    );
    check(
      recipe.fields.ingredients[1].amount == const Amount.toTaste(),
      'to taste variant',
    );
    check(
      recipe.fields.ingredients[2].amount == const Amount.unspecified(),
      'unspecified variant',
    );
    check(
      await parseAmount(written: '0.33') ==
          const Amount.rational(numerator: 1, denominator: 3),
      'new input snaps',
    );
    const range = Amount.range(
      lowerNumerator: 3,
      lowerDenominator: 2,
      upperNumerator: 2,
      upperDenominator: 1,
    );
    check(
      recipe.fields.ingredients[3].amount == range,
      'stored range across native bridge',
    );
    check(
      await parseAmount(written: '1 1/2 to 2') == range,
      'range parser across native bridge',
    );
    check(
      (await formatIngredientAmounts(
            ingredients: [recipe.fields.ingredients[3]],
          )).single ==
          '1 1/2–2',
      'range display across native bridge',
    );
    await expectCode(
      session.importOne(
        generation: snapshot.generation,
        fields: fields,
        operation: Operation(),
      ),
      ErrorCode.conflict,
    );
    snapshot = await session.importOne(
      generation: snapshot.generation,
      fields: fields,
      choice: DuplicateChoice.replace(id: id),
      operation: Operation(),
    );
    check(
      (await session.detail(id: id))!.revision == 2,
      'replace increments revision',
    );
    snapshot = await session.importOne(
      generation: snapshot.generation,
      fields: fields,
      choice: const DuplicateChoice.keepBoth(),
      operation: Operation(),
    );
    check(snapshot.summaries.length == 2, 'keep both identity');
    final added = await session.addShopping(
      generation: snapshot.generation,
      id: id,
      indices: [0, 1, 2],
      operation: Operation(),
    );
    snapshot = added.snapshot;
    check(
      snapshot.shopping.length == 3 &&
          snapshot.shopping.first.contributorIds.single == id,
      'source counts',
    );
    check(
      snapshot.shopping.first.quantityText == '33/100 cup',
      'quantity presentation',
    );
    final detached = await session.editShopping(
      generation: snapshot.generation,
      edit: ShoppingEdit.edit(id: snapshot.shopping.first.id, text: 'manual'),
      operation: Operation(),
    );
    check(
      detached.snapshot.shopping.first.contributorIds.isEmpty,
      'manual detach',
    );
    snapshot = await session.undoShopping(
      generation: detached.snapshot.generation,
      undo: detached.undo,
      operation: Operation(),
    );
    check(snapshot.shopping.first.contributorIds.single == id, 'targeted undo');
    final bytes = await session.backup(operation: Operation());
    final preview = await session.previewRestore(
      bytes: bytes,
      operation: Operation(),
    );
    check((await preview.report()).skipped == 2, 'ZIP preview');
    snapshot = await session.favorite(
      generation: snapshot.generation,
      id: id,
      value: true,
      operation: Operation(),
    );
    await expectCode(
      session.restore(preview: preview, operation: Operation()),
      ErrorCode.staleWrite,
    );
    final cancelled = Operation()..cancel();
    await expectCode(
      session.delete(
        generation: snapshot.generation,
        id: id,
        operation: cancelled,
      ),
      ErrorCode.cancelled,
    );
    final beforeDelete = snapshot.generation;
    snapshot = await session.delete(
      generation: beforeDelete,
      id: id,
      operation: Operation(),
    );
    snapshot = await session.recover(
      generation: snapshot.generation,
      operation: Operation(),
    );
    check(
      (await session.detail(id: id))!.favorite,
      'favorite history and deletion recovery',
    );
    check(
      snapshot.shopping.first.contributorIds.single == id,
      'recovery source counts',
    );
    final task = await ProviderTask.newInstance(
      input: const ProviderInput(
        text: 'selected only',
        source: '',
        targetTitle: '',
        photos: [],
        mode: ProviderMode.recipe,
        existingTags: [],
      ),
      model: 'mock-model',
      operation: Operation(),
    );
    final request =
        jsonDecode(utf8.decode(await task.request())) as Map<String, dynamic>;
    check(request['store'] == false, 'provider privacy transform');
    final retry = await task.accept(status: 200, bytes: utf8.encode('{}'));
    check(retry is ProviderOutput_Retry, 'malformed retry variant');
    await task.request();
    final output = await task.accept(
      status: 200,
      bytes: utf8.encode(
        jsonEncode({
          'status': 'completed',
          'steps': [
            {
              'type': 'model_output',
              'content': [
                {
                  'type': 'text',
                  'text': jsonEncode({
                    'ingredients': [
                      {
                        'amount': '0.33',
                        'unit': 'cup',
                        'name': 'cream',
                        'prepNote': '',
                        'optional': false,
                        'section': '',
                      },
                    ],
                  }),
                },
              ],
            },
          ],
        }),
      ),
    );
    check(
      (output as ProviderOutput_Recipe)
              .field0
              .fields
              .ingredients
              .single
              .amount ==
          const Amount.rational(numerator: 1, denominator: 3),
      'provider typed written output',
    );
    final recipeTask = await ProviderTask.newInstance(
      input: const ProviderInput(
        text: 'selected recipe',
        source: '',
        targetTitle: '',
        photos: [],
        mode: ProviderMode.recipe,
        existingTags: [],
      ),
      model: 'mock-model',
      operation: Operation(),
    );
    await recipeTask.request();
    final recipeOutput = await recipeTask.accept(
      status: 200,
      bytes: utf8.encode(
        jsonEncode({
          'status': 'completed',
          'steps': [
            {
              'type': 'model_output',
              'content': [
                {
                  'type': 'text',
                  'text': jsonEncode({
                    'title': 'Mock recipe',
                    'description': '',
                    'servings': '',
                    'prepTime': '',
                    'cookTime': '',
                    'totalTime': '',
                    'source': '',
                    'tags': [],
                    'notes': '',
                    'steps': ['Stir.'],
                    'ingredients': [],
                  }),
                },
              ],
            },
          ],
        }),
      ),
    );
    check(
      (recipeOutput as ProviderOutput_Recipe).field0.fields.title ==
          'Mock recipe',
      'provider recipe variant',
    );
    final manual = await session.editShopping(
      generation: snapshot.generation,
      edit: const ShoppingEdit.addManual(text: 'native manual'),
      operation: Operation(),
    );
    final manualId = manual.snapshot.shopping.last.id;
    final checked = await session.editShopping(
      generation: manual.snapshot.generation,
      edit: ShoppingEdit.check(ids: [manualId], checked: true),
      operation: Operation(),
    );
    check(checked.snapshot.shopping.last.checked, 'check variant');
    final removed = await session.editShopping(
      generation: checked.snapshot.generation,
      edit: ShoppingEdit.remove(ids: [manualId]),
      operation: Operation(),
    );
    snapshot = removed.snapshot;
    check(snapshot.shopping.length == 3, 'remove variant');
    streamToken.cancel();
    // Keep the Dart port open until Rust acknowledges subscription cancellation.
    while (await events.moveNext().timeout(const Duration(seconds: 5))) {}
    await events.cancel();
    await session.close();
    session = await CoreSession.open(privateRoot: root.path);
    final reopened = await session.snapshot();
    check(
      reopened.generation == snapshot.generation &&
          reopened.shopping.length == 3,
      'restart durability',
    );
  } finally {
    streamToken.cancel();
    await events.cancel();
    await session.close();
    await root.delete(recursive: true);
  }
}
