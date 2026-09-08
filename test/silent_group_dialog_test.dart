import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/common/widgets/silent_group_dialog.dart';
import 'package:fourier/services/feed_silent_settings_service.dart';

import 'support/hive_test_helper.dart';

void main() {
  setUp(HiveTestHelper.setUp);
  tearDown(HiveTestHelper.tearDown);

  testWidgets('canceling assignment preserves the current group', (
    tester,
  ) async {
    final group = (await tester.runAsync(() async {
      final group = await FeedSilentSettingsService.createGroup('技术资料');
      await FeedSilentSettingsService.moveToGroup('a', group.id);
      return group;
    }))!;
    SilentGroupAssignment? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showSilentGroupAssignmentDialog(
                  context,
                  feedId: 'a',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('技术资料'), findsOneWidget);
    expect(find.text('取消静默'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(FeedSilentSettingsService.groupIdFor('a'), group.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid names stay in the dialog; valid name returns trimmed', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showSilentGroupNameDialog(context);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '未分组');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.textContaining('不能使用'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  技术资料  ');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(result, '技术资料');
    expect(tester.takeException(), isNull);
  });
}
