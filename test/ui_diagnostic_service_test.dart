import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/services/ui_diagnostic_service.dart';

void main() {
  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('fourier-ui-log-'),
  );
  tearDown(() async => directory.delete(recursive: true));

  test('serial events remain ordered with bounded pending work', () async {
    final file = File('${directory.path}/ui.jsonl');
    final writer = UiDiagnosticWriter(file);
    for (var i = 0; i < 100; i++) {
      writer.record({'event': 'test', 'id': i});
    }
    await writer.flush();
    final rows = (await file.readAsLines())
        .map((s) => jsonDecode(s) as Map)
        .toList();
    expect(rows.length, 64);
    expect(
      rows.map((r) => r['id']),
      orderedEquals(List.generate(64, (i) => i)),
    );
    writer.record({'event': 'recovered'});
    await writer.flush();
    expect((await file.readAsLines()).length, 65);
  });

  test(
    'rotation retains one previous file and does not lose the new event',
    () async {
      final file = File('${directory.path}/ui.jsonl');
      final writer = UiDiagnosticWriter(file, maxBytes: 1);
      for (var i = 0; i < 3; i++) {
        writer.record({'id': i});
        await writer.flush();
      }
      expect(jsonDecode(await file.readAsString())['id'], 2);
      expect(
        jsonDecode(await File('${file.path}.previous').readAsString())['id'],
        1,
      );
    },
  );

  test('storage failure is swallowed and later events can recover', () async {
    final blocker = File('${directory.path}/blocked');
    await blocker.writeAsString('not a directory');
    final file = File('${blocker.path}/ui.jsonl');
    final writer = UiDiagnosticWriter(file);
    writer.record({'event': 'failed'});
    await writer.flush();
    await blocker.delete();
    writer.record({'event': 'recovered'});
    await writer.flush();
    expect(jsonDecode(await file.readAsString())['event'], 'recovered');
  });
}
