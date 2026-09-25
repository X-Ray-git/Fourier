import 'package:fourier/common/widgets/app_glass_selection_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

enum _TestAction { copy, save }

void main() {
  for (final atEdge in [false, true]) {
    testWidgets('selection close anchor and long title (edge: $atEdge)', (
      tester,
    ) async {
      const title = '用于验证返回按钮预留空间的很长很长的选择面板标题';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(atEdge ? 0 : 16),
              child: Align(
                alignment: Alignment.topRight,
                child: AppGlassMorphSelectionButton<int>(
                  value: 0,
                  title: title,
                  titleIcon: Icons.sort_rounded,
                  tooltip: '范围',
                  options: const [
                    AppGlassSelectionOption(
                      value: 0,
                      label: '未读',
                      icon: Icons.filter_alt_rounded,
                    ),
                    AppGlassSelectionOption(
                      value: 1,
                      label: '全部',
                      icon: Icons.filter_alt_off_rounded,
                    ),
                  ],
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      final trigger = find.byIcon(Icons.filter_alt_rounded);
      final center = tester.getCenter(trigger);
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      final close = find.byIcon(Icons.keyboard_arrow_up_rounded);
      // Existing viewport avoidance moves the entire panel 8px inward at
      // the extreme corner; header padding must add no further movement.
      final expected = center + (atEdge ? const Offset(-8, 8) : Offset.zero);
      expect((tester.getCenter(close) - expected).distance, lessThan(0.01));
      final hitTarget = find
          .ancestor(of: close, matching: find.byType(GestureDetector))
          .first;
      expect(tester.getSize(hitTarget), const Size(34, 34));
      expect(
        tester.getRect(find.text(title)).right,
        lessThan(tester.getRect(hitTarget).left),
      );
      expect(tester.takeException(), isNull);
      // The transparent strip outside the 26px visible circle is clickable.
      await tester.tapAt(expected + const Offset(15, 0));
      await tester.pumpAndSettle();
      expect(close, findsNothing);
      expect(find.byIcon(Icons.filter_alt_rounded), findsOneWidget);
    });
  }

  testWidgets('morph action button invokes commands without a selected row', (
    tester,
  ) async {
    _TestAction? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: AppGlassMorphActionButton<_TestAction>(
              actions: const [
                AppGlassSelectionOption(
                  value: _TestAction.copy,
                  label: '复制',
                  icon: Icons.copy_rounded,
                ),
                AppGlassSelectionOption(
                  value: _TestAction.save,
                  label: '保存',
                  icon: Icons.save_rounded,
                ),
              ],
              title: '导出',
              titleIcon: Icons.ios_share_rounded,
              triggerIcon: Icons.ios_share_rounded,
              tooltip: '导出',
              onSelected: (value) => selected = value,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.ios_share_rounded).first);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_rounded), findsNothing);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(selected, _TestAction.save);
  });
}
