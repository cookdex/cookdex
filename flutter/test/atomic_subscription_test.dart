import 'dart:async';
import 'dart:typed_data';

import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_store_test.dart' show FakeRepository, recipe, settle;

class _AtomicRepository extends FakeRepository
    implements SnapshotSubscriptionRepository {
  _AtomicRepository() : super([recipe('a')]);
  bool initialSnapshot = true;
  bool fail = false;
  bool closed = false;
  bool failSnapshot = false;
  int subscriptions = 0;
  @override
  Stream<CollectionEvent> subscribe() {
    subscriptions++;
    if (closed) return const Stream.empty();
    if (fail) return Stream.error(StateError('subscription unavailable'));
    return Stream.multi((sink) {
      final listener = events.stream.listen(
        sink.add,
        onError: sink.addError,
        onDone: sink.close,
      );
      if (initialSnapshot) sink.add(CollectionEvent.snapshot(current));
      sink.onCancel = listener.cancel;
    });
  }

  @override
  Future<CollectionSnapshot> snapshot() {
    if (failSnapshot) {
      snapshotCalls++;
      return Future.error(StateError('snapshot unavailable'));
    }
    return super.snapshot();
  }
}

void main() {
  late _AtomicRepository repository;
  late LocalPreferences prefs;
  late RecipeStore store;
  setUp(() {
    repository = _AtomicRepository();
    prefs = LocalPreferences.memory();
    store = RecipeStore(repository, prefs);
  });
  tearDown(() {
    store.dispose();
    prefs.dispose();
  });
  test('initial snapshot is sufficient and changes remain live', () async {
    await store.initialize();
    expect(repository.snapshotCalls, 0);
    expect(store.loading, isFalse);
    expect(store.visibleRecipes.single.id, 'a');
    repository.changed(recipe('b'));
    await settle();
    expect(store.summaries.map((r) => r.id), ['a', 'b']);
    expect(repository.snapshotCalls, 1);
    await store.deleteRecipe('a');
    expect(store.summaries.single.id, 'b');
    await store.restoreBackup(await store.previewRestore(Uint8List(0)));
    expect(store.summaries.map((r) => r.id), ['b', 'restored']);
  });
  test('initialization waits for the actual subscription snapshot', () async {
    repository.initialSnapshot = false;
    var finished = false;
    final pending = store.initialize().then((_) => finished = true);
    await settle();
    expect(finished, isFalse);
    expect(repository.snapshotCalls, 0);
    repository.events.add(CollectionEvent.snapshot(repository.current));
    await pending;
    expect(store.loading, isFalse);
  });
  test('a failed subscription falls back to an ordinary snapshot', () async {
    repository.fail = true;
    await store.initialize();
    expect(repository.snapshotCalls, 1);
    expect(store.summaries.single.id, 'a');
    expect(store.loading, isFalse);
  });
  test('disposal releases initialization waiting for the stream', () async {
    repository.initialSnapshot = false;
    final pending = store.initialize();
    store.dispose();
    // Replace only the test variable to keep tearDown from disposing twice.
    store = RecipeStore(FakeRepository([]), prefs);
    await pending;
  });
  test(
    'early clean close falls back, and failed snapshots allow Retry',
    () async {
      repository.closed = true;
      repository.failSnapshot = true;
      await store.initialize();
      expect(repository.snapshotCalls, 1);
      expect(store.loading, isFalse);
      expect(store.error, contains('snapshot unavailable'));
      repository.failSnapshot = false;
      await store.refresh();
      expect(store.summaries.single.id, 'a');
      expect(store.error, isNull);
    },
  );
  test('reconnection uses one atomic snapshot and current data', () async {
    await store.initialize();
    repository.events.addError(StateError('lost'));
    await settle();
    repository.recipes['b'] = recipe('b');
    repository.generation++;
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(repository.subscriptions, 2);
    expect(repository.snapshotCalls, 0);
    expect(store.summaries.map((r) => r.id), ['a', 'b']);
    expect(store.error, isNull);
  });
}
