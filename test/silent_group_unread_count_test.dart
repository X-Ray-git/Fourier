import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:fourier/models/article.dart';
import 'package:fourier/models/feed.dart';
import 'package:fourier/pages/subscriptions/subscriptions_controller.dart';
import 'package:fourier/pages/timeline/timeline_controller.dart';
import 'package:fourier/services/account_service.dart';
import 'package:fourier/services/article_state_notifier.dart';
import 'package:fourier/services/feed_silent_settings_service.dart';
import 'package:fourier/services/local_article_db_service.dart';
import 'package:fourier/utils/storage.dart';

import 'support/hive_test_helper.dart';

class _LocalSubscriptions extends SubscriptionsController {
  @override
  Future<void> loadData() async => refreshUnreadCounts();
}

ArticleModel _article(String id, String feedId, {bool read = false}) =>
    ArticleModel(
      entryId: id,
      feedId: feedId,
      feedTitle: 'Synthetic',
      title: id,
      url: '',
      isRead: read,
    );

void main() {
  setUp(() async {
    await HiveTestHelper.setUp();
    LocalArticleDbService.invalidateCache();
    Get.testMode = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('io.github.xraygit.fourier/badge'),
          (_) async => null,
        );
  });
  tearDown(() async {
    Get.reset();
    await HiveTestHelper.tearDown();
  });

  test(
    'group badge includes retained feeds and ignores catalog search',
    () async {
      final group = await FeedSilentSettingsService.createGroup('Daily');
      for (final id in ['current', 'retired']) {
        await FeedSilentSettingsService.setSilent(id, true, groupId: group.id);
      }
      final articles = [
        _article('a', 'current'),
        _article('b', 'retired'),
        _article('c', 'retired', read: true),
        _article('d', 'ordinary'),
      ];
      LocalArticleDbService.upsertMany(articles, forceReplace: true);
      final subs = SubscriptionsController();
      subs.viewNodes.assignAll([
        SourceViewNode(
          view: 0,
          name: 'Articles',
          categories: [
            SourceCategoryNode(
              name: 'Category',
              feeds: [FeedModel(feedId: 'current', title: 'Current')],
            ),
          ],
        ),
      ]);
      subs.refreshUnreadCounts();
      final timeline = TimelineController();
      timeline.allArticles.assignAll(articles);
      timeline.setTimelineScope(silent: true, silentGroupId: group.id);
      expect(subs.silentGroups.single.feeds.length, 1);
      expect(subs.unreadForSilentGroup(group.id), 2);
      expect(subs.unreadForSilentGroup(group.id), timeline.articles.length);
      expect(subs.unreadFor('current'), 0);
      expect(subs.unreadFor('ordinary'), 1);
      subs.updateSearchQuery('does-not-match');
      expect(subs.silentGroups.single.feeds, isEmpty);
      expect(subs.unreadForSilentGroup(group.id), 2);
      timeline.setViewMode(TimelineViewMode.all);
      expect(timeline.articles.length, 3);
      expect(subs.unreadForSilentGroup(group.id), 2);
    },
  );

  test(
    'read/unread and batch notifications update retained-feed counts',
    () async {
      Get.put(AccountService());
      final group = await FeedSilentSettingsService.createGroup('Daily');
      await FeedSilentSettingsService.setSilent(
        'retired',
        true,
        groupId: group.id,
      );
      final articles = [_article('a', 'retired'), _article('b', 'retired')];
      LocalArticleDbService.upsertMany(articles, forceReplace: true);
      final subs = Get.put<SubscriptionsController>(_LocalSubscriptions());
      final timeline = TimelineController();
      timeline.allArticles.assignAll(articles);
      timeline.setTimelineScope(silent: true, silentGroupId: group.id);
      void expectCount(int count) {
        expect(subs.unreadForSilentGroup(group.id), count);
        expect(timeline.articles.length, count);
      }

      expectCount(2);
      timeline.markAsReadLocal('a');
      expectCount(1);
      timeline.markAsUnreadLocal('a');
      expectCount(2);
      timeline.setManyReadStatesLocal(articles, isRead: true);
      expectCount(0);
      timeline.setManyReadStatesLocal(articles, isRead: false);
      expectCount(2);
      await Get.delete<SubscriptionsController>(force: true);
    },
  );

  test(
    'full and single-feed counts honor both pending read overrides',
    () async {
      final group = await FeedSilentSettingsService.createGroup('Daily');
      await FeedSilentSettingsService.setSilent(
        'retired',
        true,
        groupId: group.id,
      );
      final a = _article('a', 'retired');
      final b = _article('b', 'retired', read: true);
      LocalArticleDbService.upsertMany([a, b], forceReplace: true);
      await GStorage.readStatus.put('a', true);
      await GStorage.readStatus.put('b', false);
      final subs = SubscriptionsController()..refreshUnreadCounts();
      final timeline = TimelineController();
      timeline.allArticles.assignAll(
        LocalArticleDbService.mergeReadOverrides([a, b]),
      );
      timeline.setTimelineScope(silent: true, silentGroupId: group.id);
      expect(timeline.articles.single.entryId, 'b');
      expect(subs.unreadForSilentGroup(group.id), 1);
      await GStorage.readStatus.put('a', false);
      subs.refreshUnreadCounts('a');
      expect(subs.unreadForSilentGroup(group.id), 2);
      subs.refreshUnreadCounts();
      expect(subs.unreadForSilentGroup(group.id), 2);
    },
  );

  test(
    'moving or deleting a group retains unread history under its new scope',
    () async {
      Get.put(AccountService());
      final a = await FeedSilentSettingsService.createGroup('Daily');
      final b = await FeedSilentSettingsService.createGroup('Other');
      await FeedSilentSettingsService.setSilent('retired', true, groupId: a.id);
      LocalArticleDbService.upsertOne(_article('entry', 'retired'));
      final subs = Get.put<SubscriptionsController>(_LocalSubscriptions());
      expect(subs.unreadForSilentGroup(a.id), 1);
      await FeedSilentSettingsService.moveToGroup('retired', b.id);
      expect(subs.unreadForSilentGroup(a.id), 0);
      expect(subs.unreadForSilentGroup(b.id), 1);
      await FeedSilentSettingsService.deleteGroup(b.id);
      expect(subs.unreadForSilentGroup(null), 1);
      expect(
        subs.unreadForSilentGroup(FeedSilentSettingsService.ungroupedId),
        1,
      );
      expect(subs.silentGroups.last.name, '未分组');
      expect(subs.silentGroups.last.feeds, isEmpty);
      await FeedSilentSettingsService.setSilent('retired', false);
      expect(subs.unreadForSilentGroup(null), 0);
      expect(subs.unreadFor('retired'), 1);
      expect(subs.silentGroups.any((g) => g.id == null), false);
      await Get.delete<SubscriptionsController>(force: true);
    },
  );

  test(
    'deletion notification clears the previous unread contribution',
    () async {
      Get.put(AccountService());
      await FeedSilentSettingsService.setSilent('retired', true);
      LocalArticleDbService.upsertOne(_article('entry', 'retired'));
      final subs = Get.put<SubscriptionsController>(_LocalSubscriptions());
      expect(subs.unreadForSilentGroup(null), 1);
      await GStorage.articleDb.delete('entry');
      LocalArticleDbService.invalidateCache();
      ArticleStateNotifier.tick('entry');
      expect(subs.unreadForSilentGroup(null), 0);
      await Get.delete<SubscriptionsController>(force: true);
    },
  );
}
