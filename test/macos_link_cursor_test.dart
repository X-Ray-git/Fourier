import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/utils/macos_link_cursor.dart';

void main() {
  testWidgets('samples are bounded, throttled and cancelled on exit', (
    tester,
  ) async {
    var now = DateTime(2026);
    var reads = 0;
    final records = <Map<String, Object?>>[];
    final sampler = CursorDiagnosticSampler(
      now: () => now,
      readNative: () async {
        reads++;
        return {'current': 'pointingHand', 'url': 'PRIVATE_URL'};
      },
      record: records.add,
    );
    final end = sampler.begin(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    await tester.pump(const Duration(milliseconds: 420));
    await tester.pump(const Duration(seconds: 10));
    expect(reads, 3); // No continuous sampling after 600ms.
    expect(records.toString(), isNot(contains('PRIVATE_URL')));
    sampler.begin(1)(); // Clock still within rate limit.
    expect(reads, 3);
    end();
    end();
    expect(
      records.where((r) => r['event'] == 'cursor_probe_end'),
      hasLength(1),
    );
    now = now.add(const Duration(seconds: 2));
    final nextEnd = sampler.begin(1);
    await tester.pump();
    nextEnd();
    await tester.pump(const Duration(seconds: 1));
    expect(reads, 4); // Both delayed samples cancelled.
  });

  testWidgets('late native response after exit is discarded', (tester) async {
    final response = Completer<Map<Object?, Object?>?>();
    final records = <Map<String, Object?>>[];
    final sampler = CursorDiagnosticSampler(
      readNative: () => response.future,
      record: records.add,
    );
    final end = sampler.begin(1);
    end();
    response.complete({'current': 'arrow'});
    await tester.pump(const Duration(seconds: 1));
    expect(records.map((r) => r['event']), [
      'cursor_probe_start',
      'cursor_probe_end',
    ]);
  });

  testWidgets('native failure is bounded and does not expose error text', (
    tester,
  ) async {
    final records = <Map<String, Object?>>[];
    final end = CursorDiagnosticSampler(
      readNative: () async => throw StateError('PRIVATE_CONTENT'),
      record: records.add,
    ).begin(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    await tester.pump(const Duration(milliseconds: 420));
    end();
    expect(
      records.where((r) => r['event'] == 'cursor_probe_unavailable'),
      hasLength(3),
    );
    expect(records.toString(), isNot(contains('PRIVATE_CONTENT')));
  });

  testWidgets('exiting before platform acknowledgement starts no probe', (
    tester,
  ) async {
    final acknowledged = Completer<void>();
    final messenger = tester.binding.defaultBinaryMessenger;
    var queries = 0;
    messenger.setMockMethodCallHandler(SystemChannels.mouseCursor, (
      call,
    ) async {
      if ((call.arguments as Map)['kind'] == 'click') await acknowledged.future;
      return null;
    });
    const channel = MethodChannel('io.github.xraygit.fourier/cursor');
    messenger.setMockMethodCallHandler(channel, (call) async {
      queries++;
      return {'current': 'arrow'};
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: MouseRegion(
            cursor: MacOSLinkCursor.instance,
            child: SizedBox(width: 100, height: 100),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(10, 10));
    await mouse.moveTo(const Offset(400, 300));
    await tester.pump();
    await mouse.moveTo(const Offset(10, 10));
    await mouse.removePointer();
    acknowledged.complete();
    await tester.pump(const Duration(seconds: 1));
    expect(queries, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.mouseCursor, null);
  });

  testWidgets(
    'link activation delegates click and observes without resetting it',
    (tester) async {
      final activations = <Object?>[];
      final queries = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.mouseCursor, (
        call,
      ) async {
        activations.add(call.arguments);
        return null;
      });
      const channel = MethodChannel('io.github.xraygit.fourier/cursor');
      messenger.setMockMethodCallHandler(channel, (call) async {
        queries.add(call.method);
        return {'current': 'arrow'};
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: MouseRegion(
              cursor: MacOSLinkCursor.instance,
              child: SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      );
      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        pointer: 1,
      );
      await mouse.addPointer(location: const Offset(10, 10));
      await mouse.moveTo(const Offset(400, 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      await tester.pump(const Duration(milliseconds: 420));
      expect(activations, [
        {'device': 1, 'kind': 'basic'},
        {'device': 1, 'kind': 'click'},
      ]);
      expect(queries, List.filled(3, 'getCursorDiagnostics'));
      await mouse.moveTo(const Offset(10, 10));
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockMethodCallHandler(SystemChannels.mouseCursor, null);
    },
  );
}
