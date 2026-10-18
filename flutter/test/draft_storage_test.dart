import 'dart:io';

import 'package:cookdex/draft_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encoded snapshots preserve ordering, UTF-8 limits and clear', () async {
    final directory = await Directory.systemTemp.createTemp('cookdex-draft-');
    addTearDown(() => directory.delete(recursive: true));
    final storage = FileDraftStorage(
      '${directory.path}/draft.json',
      limitBytes: 24,
    );
    final first = storage.writeEncoded('{"title":"one"}');
    final second = storage.writeEncoded('{"title":"two"}');
    await Future.wait([first, second]);
    expect((await storage.read())!['title'], 'two');
    await expectLater(
      storage.writeEncoded('{"title":"🥣🥣🥣🥣"}'),
      throwsFormatException,
    );
    expect((await storage.read())!['title'], 'two');
    await storage.clear();
    expect(await storage.read(), isNull);
  });
  test(
    'draft survives relaunch with raw inputs and canonical base intact',
    () async {
      final directory = await Directory.systemTemp.createTemp('cookdex-draft-');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/draft.json';
      final storage = FileDraftStorage(path);
      final value = <String, dynamic>{
        'amount': '0.33',
        'base': {'id': 'synthetic', 'numerator': 33, 'denominator': 100},
        'pendingPaste': '1-2 potatoes',
      };
      final write = storage.write(value);
      value['amount'] = 'later change';
      await write;
      final restored = await FileDraftStorage(path).read();
      expect(restored!['amount'], '0.33');
      expect(restored['base'], value['base']);
      expect(restored['pendingPaste'], '1-2 potatoes');
      await storage.write({'amount': 'newer'});
      expect((await storage.read())!['amount'], 'newer');
      final queued = storage.write({'amount': 'queued'});
      final cleared = storage.clear();
      await queued;
      await cleared;
      expect(await FileDraftStorage(path).read(), isNull);
    },
  );

  test(
    'draft read/write failures are visible and do not poison retries',
    () async {
      final directory = await Directory.systemTemp.createTemp('cookdex-draft-');
      addTearDown(() => directory.delete(recursive: true));
      final parent = File('${directory.path}/parent');
      await parent.writeAsString('block directory creation');
      final storage = FileDraftStorage('${parent.path}/draft.json');
      await expectLater(
        storage.write({'title': 'Synthetic'}),
        throwsA(isA<FileSystemException>()),
      );
      await parent.delete();
      await storage.write({'title': 'Synthetic'});
      expect((await storage.read())!['title'], 'Synthetic');
      await File(storage.path).writeAsString('{broken');
      await expectLater(storage.read(), throwsFormatException);
      expect(await File(storage.path).readAsString(), '{broken');
    },
  );
}
