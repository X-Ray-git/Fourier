import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/models/article.dart';
import 'package:fourier/services/local_article_db_service.dart';
import 'package:fourier/utils/storage.dart';

import 'support/hive_test_helper.dart';

ArticleModel _article(String id, {required bool isRead}) => ArticleModel(
  entryId: id,
  feedId: 'feed-1',
  feedTitle: 'Feed',
  title: 'Article $id',
  url: 'https://example.com/$id',
  isRead: isRead,
);

void main() {
  setUp(HiveTestHelper.setUp);
  tearDown(HiveTestHelper.tearDown);

  test('mergeReadOverrides applies only differing local choices', () async {
    final unchanged = _article('unchanged', isRead: false);
    final matching = _article('matching', isRead: true);
    final overridden = _article('overridden', isRead: false);
    await GStorage.readStatus.put('matching', true);
    await GStorage.readStatus.put('overridden', true);

    final merged = LocalArticleDbService.mergeReadOverrides([
      unchanged,
      matching,
      overridden,
    ]);

    expect(identical(merged[0], unchanged), isTrue);
    expect(identical(merged[1], matching), isTrue);
    expect(merged[2].isRead, isTrue);
    expect(identical(merged[2], overridden), isFalse);
  });

  test('removes transient fetch state with a deleted article', () async {
    await GStorage.setting.put('readability_fetched_entry-1', true);
    await GStorage.setting.put('readability_fetch_state_entry-1', {
      'attempts': 2,
    });
    await GStorage.setting.put('inbox_detail_fetched_entry-1', true);
    await GStorage.setting.put('readability_fetched_other-entry', true);

    await LocalArticleDbService.removeArticleTransientState(['entry-1']);

    expect(GStorage.setting.get('readability_fetched_entry-1'), isNull);
    expect(GStorage.setting.get('readability_fetch_state_entry-1'), isNull);
    expect(GStorage.setting.get('inbox_detail_fetched_entry-1'), isNull);
    expect(GStorage.setting.get('readability_fetched_other-entry'), isTrue);
  });

  test(
    'reconciles read overrides only when the server confirms them',
    () async {
      await GStorage.readStatus.put('pending-read', true);
      await GStorage.readStatus.put('pending-unread', false);

      expect(
        LocalArticleDbService.reconcileUnreadSnapshotEntry(
          'pending-read',
          appearsUnread: true,
        ),
        isFalse,
      );
      expect(GStorage.readStatus.get('pending-read'), isTrue);

      expect(
        LocalArticleDbService.reconcileUnreadSnapshotEntry(
          'pending-read',
          appearsUnread: false,
        ),
        isTrue,
      );
      expect(GStorage.readStatus.get('pending-read'), isNull);

      expect(
        LocalArticleDbService.reconcileUnreadSnapshotEntry(
          'pending-unread',
          appearsUnread: false,
        ),
        isFalse,
      );
      expect(GStorage.readStatus.get('pending-unread'), isFalse);

      expect(
        LocalArticleDbService.reconcileUnreadSnapshotEntry(
          'pending-unread',
          appearsUnread: true,
        ),
        isFalse,
      );
      expect(GStorage.readStatus.get('pending-unread'), isNull);

      expect(
        LocalArticleDbService.reconcileUnreadSnapshotEntry(
          'server-read',
          appearsUnread: false,
        ),
        isTrue,
      );
    },
  );
}
