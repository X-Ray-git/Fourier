import 'package:fourier/common/widgets/app_glass_selection_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

enum _TestAction { copy, save }

void main() {
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
