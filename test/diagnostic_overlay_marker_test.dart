import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:fourier/common/widgets/diagnostic_overlay_marker.dart';
import 'package:fourier/services/ui_diagnostic_service.dart';

import 'support/hive_test_helper.dart';

void main() {
  setUp(HiveTestHelper.setUp);
  tearDown(HiveTestHelper.tearDown);
  testWidgets(
    'mounted overlay markers pair events without logging child text',
    (tester) async {
      final previousError = FlutterError.onError;
      final previousPlatform = PlatformDispatcher.instance.onError;
      final previousBuilder = ErrorWidget.builder;
      try {
        await tester.runAsync(UiDiagnosticService.initialize);
        Widget marker(String kind, String label) => DiagnosticOverlayMarker(
          kind: kind,
          child: Text(label, textDirection: TextDirection.ltr),
        );
        await tester.pumpWidget(
          marker('feedbackToast', 'PRIVATE_FIRST_CONTENT'),
        );
        await tester.pumpWidget(
          marker('feedbackToast', 'PRIVATE_UPDATED_CONTENT'),
        );
        await tester.pumpWidget(
          marker('otherOverlay', 'PRIVATE_OTHER_CONTENT'),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        var flushed = false;
        UiDiagnosticService.flushForTesting().then((_) => flushed = true);
        for (var i = 0; i < 200 && !flushed; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(flushed, true);
        final text = (await tester.runAsync(() async {
          final root = await getApplicationSupportDirectory();
          return File('${root.path}/diagnostics/ui.jsonl').readAsString();
        }))!;
        final rows = text
            .split('\n')
            .where((s) => s.isNotEmpty)
            .map((s) => jsonDecode(s) as Map)
            .where((row) => row['event'] != 'session_start')
            .toList();
        expect(rows.map((r) => r['event']), [
          'overlay_open',
          'overlay_close',
          'overlay_open',
          'overlay_close',
        ]);
        expect(rows[0]['kind'], 'feedbackToast');
        expect(rows[1]['id'], rows[0]['id']);
        expect(rows[2]['kind'], 'otherOverlay');
        expect(rows[3]['id'], rows[2]['id']);
        expect(text, isNot(contains('PRIVATE_')));
      } finally {
        FlutterError.onError = previousError;
        PlatformDispatcher.instance.onError = previousPlatform;
        ErrorWidget.builder = previousBuilder;
      }
    },
  );
}
