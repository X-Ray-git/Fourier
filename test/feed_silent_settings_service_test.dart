import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fourier/models/article.dart';
import 'package:fourier/models/feed.dart';
import 'package:fourier/pages/subscriptions/subscriptions_controller.dart';
import 'package:fourier/pages/timeline/timeline_controller.dart';
import 'package:fourier/services/feed_silent_settings_service.dart';
import 'package:fourier/services/settings_backup_service.dart';
import 'package:fourier/utils/storage.dart';

import 'support/hive_test_helper.dart';

void main() {
  setUp(HiveTestHelper.setUp);
  tearDown(HiveTestHelper.tearDown);

  test('legacy silent feeds naturally remain ungrouped', () async {
    await GStorage.setting.put('feed_silent_feed-a', true);

    expect(FeedSilentSettingsService.isSilent('feed-a'), isTrue);
    expect(FeedSilentSettingsService.groupIdFor('feed-a'), isNull);
    expect(FeedSilentSettingsService.feedCountForGroup(null), 1);
  });

  test('create, assign, and rename preserve stable group identity', () async {
    final group = await FeedSilentSettingsService.createGroup('技术资料');
    await FeedSilentSettingsService.moveToGroup('feed-a', group.id);
    await FeedSilentSettingsService.renameGroup(group.id, '技术文章');

    expect(FeedSilentSettingsService.isSilent('feed-a'), isTrue);
    expect(FeedSilentSettingsService.groupIdFor('feed-a'), group.id);
    expect(FeedSilentSettingsService.groupById(group.id)?.name, '技术文章');
  });

  test(
    'deleting a group keeps its feeds silent and makes them ungrouped',
    () async {
      final group = await FeedSilentSettingsService.createGroup('稍后整理');
      await FeedSilentSettingsService.moveToGroup('feed-a', group.id);

      await FeedSilentSettingsService.deleteGroup(group.id);

      expect(FeedSilentSettingsService.isSilent('feed-a'), isTrue);
      expect(FeedSilentSettingsService.groupIdFor('feed-a'), isNull);
      expect(FeedSilentSettingsService.feedCountForGroup(null), 1);
    },
  );

  test('canceling silent clears the current group assignment', () async {
    final group = await FeedSilentSettingsService.createGroup('行业资讯');
    await FeedSilentSettingsService.moveToGroup('feed-a', group.id);

    await FeedSilentSettingsService.setSilent('feed-a', false);

    expect(FeedSilentSettingsService.isSilent('feed-a'), isFalse);
    expect(
      GStorage.setting.get(
        '${FeedSilentSettingsService.assignmentKeyPrefix}feed-a',
      ),
      isNull,
    );
  });

  test('reserved and duplicate names are rejected', () async {
    await FeedSilentSettingsService.createGroup('技术资料');

    expect(
      () => FeedSilentSettingsService.createGroup('技术资料'),
      throwsFormatException,
    );
    expect(
      () => FeedSilentSettingsService.createGroup('未分组'),
      throwsFormatException,
    );
  });

  test('group ordering is stable and bounded', () async {
    final a = await FeedSilentSettingsService.createGroup('A');
    final b = await FeedSilentSettingsService.createGroup('B');
    await FeedSilentSettingsService.moveGroup(b.id, -1);
    await FeedSilentSettingsService.moveGroup(b.id, -1);
    expect(FeedSilentSettingsService.groups.map((g) => g.id), [b.id, a.id]);
    await FeedSilentSettingsService.moveGroup(b.id, 1);
    expect(FeedSilentSettingsService.groups.map((g) => g.id), [a.id, b.id]);
  });

  test('malformed definitions never return a stale cached group', () async {
    await FeedSilentSettingsService.createGroup('A');
    await GStorage.setting.put(FeedSilentSettingsService.groupsKey, 'invalid');
    expect(FeedSilentSettingsService.groups, isEmpty);
    expect(FeedSilentSettingsService.groups, isEmpty);
    expect(
      () => FeedSilentSettingsService.parseGroupsJson(
        '[{"id":"__ungrouped__","name":"A"}]',
      ),
      throwsFormatException,
    );
  });

  test('group migration preserves the source Folo category', () async {
    final feed = FeedModel(feedId: 'a', title: 'Source', category: 'Folo A');
    final subscriptions = SubscriptionsController();
    subscriptions.viewNodes.value = [
      SourceViewNode(
        view: 0,
        name: 'Articles',
        categories: [
          SourceCategoryNode(name: 'Folo A', feeds: [feed]),
        ],
      ),
    ];
    final group = await FeedSilentSettingsService.createGroup('Local B');
    expect(subscriptions.silentGroups.single.feeds, isEmpty);
    await FeedSilentSettingsService.moveToGroup('a', group.id);
    expect(subscriptions.sidebarNodes, isEmpty);
    expect(subscriptions.silentGroups.single.feeds.single, same(feed));
    await FeedSilentSettingsService.deleteGroup(group.id);
    expect(subscriptions.silentGroups.single.name, '未分组');
    expect(subscriptions.silentGroups.single.feeds.single, same(feed));
    await FeedSilentSettingsService.setSilent('a', false);
    expect(subscriptions.sidebarNodes.single.categories.single.name, 'Folo A');
    expect(feed.category, 'Folo A');
    expect(subscriptions.silentGroups, isEmpty);
  });

  test('group, ungrouped and ordinary scopes share one filter', () async {
    final group = await FeedSilentSettingsService.createGroup('A');
    await FeedSilentSettingsService.moveToGroup('grouped', group.id);
    await FeedSilentSettingsService.setSilent('ungrouped', true);
    final timeline = TimelineController();
    ArticleModel article(String id, {bool read = false}) => ArticleModel(
      entryId: id,
      feedId: id,
      feedTitle: id,
      title: id,
      url: '',
      isRead: read,
    );
    timeline.allArticles.value = [
      article('grouped'),
      article('ungrouped'),
      article('normal'),
      article('read', read: true),
    ];
    Set<String> ids() => timeline.articles.map((a) => a.entryId).toSet();
    timeline.setTimelineScope(silent: true);
    expect(
      timeline.selectedSilentGroupId.value,
      FeedSilentSettingsService.ungroupedId,
    );
    expect(ids(), {'ungrouped'});
    timeline.setTimelineScope(silent: true, silentGroupId: group.id);
    expect(ids(), {'grouped'});
    final key = timeline.timelineScopeKey;
    timeline.silentBatchProcessing.value = true;
    timeline.setTimelineScope();
    expect(timeline.timelineScopeKey, key);
    timeline.silentBatchProcessing.value = false;
    timeline.setTimelineScope(silent: true, silentGroupId: 'deleted');
    expect(
      timeline.selectedSilentGroupId.value,
      FeedSilentSettingsService.ungroupedId,
    );
    expect(ids(), {'ungrouped'});
    timeline.setTimelineScope();
    expect(ids(), {'normal'});
    timeline.setTimelineScope(feedId: 'grouped');
    expect(ids(), {'grouped'});
  });

  test(
    'backup round trip replaces groups; legacy backup leaves ungrouped',
    () async {
      final group = await FeedSilentSettingsService.createGroup('A');
      await FeedSilentSettingsService.moveToGroup('a', group.id);
      final payload = SettingsBackupService.parseJson(
        jsonEncode({
          'type': 'fourier_settings',
          'version': 1,
          'settings': SettingsBackupService.exportSettings(),
        }),
      );
      await FeedSilentSettingsService.createGroup('Temporary');
      await SettingsBackupService.applyPayload(payload);
      expect(FeedSilentSettingsService.groups.single.id, group.id);
      expect(FeedSilentSettingsService.groupIdFor('a'), group.id);

      await SettingsBackupService.importFromJson(
        jsonEncode({
          'type': 'fourier_settings',
          'version': 1,
          'settings': {'feed_silent_a': true},
        }),
      );
      expect(FeedSilentSettingsService.groups, isEmpty);
      expect(FeedSilentSettingsService.groupIdFor('a'), isNull);
      expect(FeedSilentSettingsService.isSilent('a'), isTrue);
    },
  );
}
