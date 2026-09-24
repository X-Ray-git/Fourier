import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/models/article.dart';
import 'package:fourier/pages/timeline/timeline_controller.dart';
import 'package:fourier/services/feed_silent_settings_service.dart';

import 'support/hive_test_helper.dart';

void main() {
  setUp(HiveTestHelper.setUp);
  tearDown(HiveTestHelper.tearDown);

  test('静默分组中的单个来源可显示未读与已读文章', () async {
    final group = await FeedSilentSettingsService.createGroup('OTHERS');
    await FeedSilentSettingsService.setSilent('sspai', true, groupId: group.id);
    await FeedSilentSettingsService.setSilent('other', true);
    final controller = TimelineController();
    controller.allArticles.addAll([
      _article('unread', 'sspai'),
      _article('read', 'sspai', isRead: true),
      _article('other', 'other'),
    ]);

    controller.setTimelineScope(silent: true, silentGroupId: group.id);
    expect(controller.articles.map((a) => a.entryId), ['unread']);

    // Matches the silent sidebar's individual source action.
    controller.setTimelineScope(silent: true, feedId: 'sspai');
    expect(controller.articles.map((a) => a.entryId), ['unread']);
    expect(controller.selectedSilentGroupId.value, isNull);
    controller.setViewMode(TimelineViewMode.all);
    expect(
      controller.articles.map((a) => a.entryId),
      containsAll(['unread', 'read']),
    );
    expect(controller.articles.length, 2);

    controller.setTimelineScope(silent: true);
    expect(controller.articles.map((a) => a.entryId), ['other']);
    controller.setTimelineScope(silent: true, silentGroupId: group.id);
    expect(controller.articles.length, 2);
  });
}

ArticleModel _article(String id, String feedId, {bool isRead = false}) =>
    ArticleModel.fromCache({
      'entryId': id,
      'feedId': feedId,
      'title': id,
      'isRead': isRead,
    });
