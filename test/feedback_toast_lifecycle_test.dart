import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:fourier/common/widgets/feedback_toast.dart';
import 'package:fourier/services/ui_diagnostic_service.dart';

import 'support/hive_test_helper.dart';

void main() {
  setUp(HiveTestHelper.setUp);
  tearDown(HiveTestHelper.tearDown);
  testWidgets(
    'queued toast requests correlate with mounted instances during page rebuilds',
    (tester) async {
      final previousError = FlutterError.onError;
      final previousPlatform = PlatformDispatcher.instance.onError;
      final previousBuilder = ErrorWidget.builder;
      final page = ValueNotifier(0);
      try {
        await tester.runAsync(UiDiagnosticService.initialize);
        await tester.pumpWidget(
          MaterialApp(
            builder: FlutterSmartDialog.init(),
            navigatorObservers: [FlutterSmartDialog.observer],
            home: Scaffold(
              body: ValueListenableBuilder<int>(
                valueListenable: page,
                builder: (_, value, _) => Navigator(
                  key: ValueKey(value),
                  onGenerateRoute: (_) => PageRouteBuilder<void>(
                    pageBuilder: (_, _, _) =>
                        const SelectionArea(child: Text('Synthetic body')),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (var i = 0; i < 12; i++) {
          page.value++;
          AppFeedback.success('PRIVATE_TITLE', 'PRIVATE_BODY');
          await tester.pump(const Duration(milliseconds: 120));
          if (i % 3 == 0) {
            SmartDialog.dismiss(status: SmartStatus.allToast);
            await tester.pump(const Duration(milliseconds: 300));
          }
          expect(tester.takeException(), isNull);
        }
        SmartDialog.dismiss(status: SmartStatus.allToast);
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        var flushed = false;
        UiDiagnosticService.flushForTesting().then((_) => flushed = true);
        for (var i = 0; i < 1000 && !flushed; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(flushed, isTrue);
        final text = await tester.runAsync(() async {
          final root = await getApplicationSupportDirectory();
          return File('${root.path}/diagnostics/ui.jsonl').readAsString();
        });
        final rows = text!
            .split('\n')
            .where((s) => s.isNotEmpty)
            .map((s) => jsonDecode(s) as Map)
            .toList();
        final requests = rows
            .where((r) => r['event'] == 'feedback_request')
            .map((r) => r['requestId'])
            .toSet();
        final opens = rows.where((r) => r['event'] == 'overlay_open').toList();
        final closes = rows
            .where((r) => r['event'] == 'overlay_close')
            .map((r) => r['id'])
            .toSet();
        expect(requests, hasLength(12));
        expect(opens, isNotEmpty);
        for (final row in opens) {
          expect(requests, contains(row['requestId']));
          expect(closes, contains(row['id']));
          expect(row['component'], '_FeedbackToast');
        }
        expect(text, isNot(contains('PRIVATE_')));
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        FlutterError.onError = previousError;
        PlatformDispatcher.instance.onError = previousPlatform;
        ErrorWidget.builder = previousBuilder;
        page.dispose();
      }
    },
  );
}
