import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/pages/settings/task_center_page.dart';
import 'package:fourier/services/local_article_db_service.dart';
import 'package:fourier/services/summary_service.dart';
import 'package:fourier/services/translation_service.dart';
import 'package:fourier/utils/storage.dart';

import 'support/hive_test_helper.dart';

void main() {
  setUp(HiveTestHelper.setUp);
  tearDown(() async {
    SummaryService.resetForAccountChange();
    TranslationService.resetForAccountChange();
    await HiveTestHelper.tearDown();
  });

  testWidgets(
    'mac failure lists stay inside task surface and return to overview',
    (tester) async {
      await tester.runAsync(() async {
        for (final id in ['summary', 'translation']) {
          await GStorage.articleDb.put(id, {
            'entryId': id,
            'feedId': 'test',
            'title': '用于验证窄窗口下长标题及操作按钮布局的文章标题' * 4,
            'content': '<p>Test content</p>',
            'url': 'https://example.com/article',
          });
        }
        LocalArticleDbService.invalidateCache();
        await GStorage.summaries.put(
          'summary',
          const SummaryRecord(
            status: SummaryStatus.error,
            errorMessage: 'Test summary failure',
            updatedAt: 1,
          ).toJson(),
        );
        await GStorage.translations.put(
          'translation',
          const TranslationRecord(
            status: TranslationStatus.error,
            errorMessage: 'Test translation failure',
            updatedAt: 1,
          ).toJson(),
        );
      });
      tester.view.physicalSize = const Size(800, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(18),
              child: TaskCenterPage(embedded: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final index in [0, 1]) {
        final button = find.text('查看失败').at(index);
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        final overviewOffset = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .pixels;
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.text(index == 0 ? '翻译失败文章' : '摘要失败文章'), findsOneWidget);
        expect(find.byType(Scaffold), findsOneWidget);
        tester.view.physicalSize = const Size(380, 500);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        tester.view.physicalSize = const Size(800, 700);
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
        await tester.pumpAndSettle();
        expect(find.text('自动摘要'), findsOneWidget);
        expect(
          tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .pixels,
          closeTo(overviewOffset, 1),
        );
        expect(find.byType(Scaffold), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
    },
    skip: !Platform.isMacOS,
  );
}
