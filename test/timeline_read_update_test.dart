import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:fourier/models/article.dart';
import 'package:fourier/pages/timeline/timeline_controller.dart';
import 'package:fourier/services/account_service.dart';
import 'package:fourier/services/article_state_notifier.dart';
import 'package:fourier/utils/storage.dart';

import 'support/hive_test_helper.dart';

void main() {
  setUp(HiveTestHelper.setUp);
  tearDown(() async {
    Get.reset();
    await HiveTestHelper.tearDown();
  });
  test('duplicate notifications skip list rebuild; real content/filter and unread changes propagate', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('io.github.xraygit.fourier/badge'),
          (_) async => null,
        );
    Get.put(AccountService());
    final controller = Get.put(TimelineController());
    final article = ArticleModel(
      entryId: 'a',
      feedId: 'f',
      feedTitle: 'Feed',
      title: 'Title',
      url: '',
    );
    await GStorage.articleDb.put('a', article.toJson());
    controller.allArticles.assignAll([article]);
    controller.setViewMode(TimelineViewMode.all);
    var updates = 0;
    final worker = ever(controller.articles, (_) => updates++);
    controller.markAsReadLocal('a');
    expect(controller.articles.single.isRead, isTrue);
    expect(updates, 1);
    ArticleStateNotifier.tick('a');
    expect(updates, 1);
    final changed =
        Map<String, dynamic>.from(GStorage.articleDb.get('a') as Map)
          ..['content'] = '<p>New content</p>'
          ..['isRejectedByAi'] = true;
    await GStorage.articleDb.put('a', changed);
    ArticleStateNotifier.tick('a');
    expect(updates, 2);
    expect(controller.articles.single.content, '<p>New content</p>');
    expect(controller.articles.single.isRejectedByAi, isTrue);
    controller.markAsUnreadLocal('a');
    expect(controller.articles.single.isRead, isFalse);
    expect(controller.filterCount.value, 1);
    worker.dispose();
  });
}
