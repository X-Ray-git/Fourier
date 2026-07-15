import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:autofolo/common/widgets/app_glass.dart';

void main() {
  Future<void> showTooltip(
    WidgetTester tester, {
    required Key targetKey,
  }) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byKey(targetKey)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    addTearDown(mouse.removePointer);
  }

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets(
    'bottom tooltip stays inside the window near the right edge',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 180));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const targetKey = ValueKey('bottom-target');

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  top: 8,
                  right: 4,
                  child: AppGlassTooltip(
                    message: '标为已读 (M) with a deliberately long label',
                    waitDuration: Duration.zero,
                    child: SizedBox(key: targetKey, width: 34, height: 34),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await showTooltip(tester, targetKey: targetKey);

      final bubble = tester.getRect(find.byType(AppGlassSurface));
      expect(bubble.left, greaterThanOrEqualTo(8));
      expect(bubble.right, lessThanOrEqualTo(312));
    },
    skip: !Platform.isMacOS,
  );

  testWidgets(
    'right tooltip flips and stays inside the bottom-right corner',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 180));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const targetKey = ValueKey('right-target');

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: AppGlassTooltip(
                    message: '保留这篇文章',
                    waitDuration: Duration.zero,
                    placement: AppGlassTooltipPlacement.right,
                    child: SizedBox(key: targetKey, width: 34, height: 34),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await showTooltip(tester, targetKey: targetKey);

      final bubble = tester.getRect(find.byType(AppGlassSurface));
      expect(bubble.left, greaterThanOrEqualTo(8));
      expect(bubble.right, lessThanOrEqualTo(312));
      expect(bubble.top, greaterThanOrEqualTo(8));
      expect(bubble.bottom, lessThanOrEqualTo(172));
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Transform && widget.alignment == Alignment.centerRight,
        ),
        findsOneWidget,
      );
    },
    skip: !Platform.isMacOS,
  );

  testWidgets(
    'bottom tooltip flips above with an animation origin near its target',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 180));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const targetKey = ValueKey('bottom-edge-target');

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  right: 40,
                  bottom: 4,
                  child: AppGlassTooltip(
                    message: '标为已读 (M)',
                    waitDuration: Duration.zero,
                    child: SizedBox(key: targetKey, width: 34, height: 34),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await showTooltip(tester, targetKey: targetKey);

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Transform && widget.alignment == Alignment.bottomCenter,
        ),
        findsOneWidget,
      );
    },
    skip: !Platform.isMacOS,
  );
}
