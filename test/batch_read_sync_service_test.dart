import 'package:autofolo/models/article.dart';
import 'package:autofolo/services/batch_read_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ArticleModel article(int id, {bool inbox = false}) => ArticleModel(
    entryId: '$id',
    feedId: 'feed-$id',
    feedTitle: 'Feed',
    title: 'Article $id',
    url: 'https://example.com/$id',
    category: inbox ? 'inbox' : 'feeds',
  );

  test('complete operation does not report compensation failures', () async {
    final articles = List.generate(3, article);
    final result = await BatchReadSyncService.transition(
      articles,
      targetIsRead: true,
      markRead: (_, {required isInbox}) async => true,
      markUnread: (_) async => false,
    );

    expect(result.allApplied, isTrue);
    expect(result.changedArticles, hasLength(3));
    expect(result.compensationAttempted, isFalse);
    expect(result.compensationFailedArticles, isEmpty);
  });

  test('later read batch failure is fully compensated', () async {
    final articles = List.generate(51, article);
    var readCalls = 0;

    final result = await BatchReadSyncService.transition(
      articles,
      targetIsRead: true,
      markRead: (_, {required isInbox}) async => ++readCalls == 1,
      markUnread: (_) async => true,
    );

    expect(result.allApplied, isFalse);
    expect(result.operationSucceededIds, hasLength(50));
    expect(result.compensationSucceededIds, hasLength(50));
    expect(result.changedArticles, isEmpty);
    expect(result.unchangedArticles, hasLength(51));
  });

  test(
    'failed compensation reports the articles left changed remotely',
    () async {
      final articles = List.generate(51, article);
      var readCalls = 0;

      final result = await BatchReadSyncService.transition(
        articles,
        targetIsRead: true,
        markRead: (_, {required isInbox}) async => ++readCalls == 1,
        markUnread: (item) async => item.entryId != '0',
      );

      expect(result.operationSucceededIds, hasLength(50));
      expect(result.compensationSucceededIds, hasLength(49));
      expect(result.compensationFailedArticles.map((item) => item.entryId), [
        '0',
      ]);
      expect(result.changedArticles.map((item) => item.entryId), ['0']);
      expect(result.unchangedArticles, hasLength(50));
    },
  );

  test(
    'partial markUnread during undo tracks the final unread subset',
    () async {
      final articles = List.generate(3, article);

      final result = await BatchReadSyncService.transition(
        articles,
        targetIsRead: false,
        markRead: (_, {required isInbox}) async => false,
        markUnread: (item) async => item.entryId != '1',
      );

      expect(result.operationSucceededIds, {'0', '2'});
      expect(result.compensationSucceededIds, isEmpty);
      expect(result.changedArticles.map((item) => item.entryId), ['0', '2']);
      expect(result.unchangedArticles.map((item) => item.entryId), ['1']);
    },
  );

  test('partial markRead during redo tracks compensation failures', () async {
    final articles = List.generate(51, article);
    var readCalls = 0;

    final result = await BatchReadSyncService.transition(
      articles,
      targetIsRead: true,
      markRead: (_, {required isInbox}) async => ++readCalls == 1,
      markUnread: (item) async => item.entryId != '7',
    );

    expect(result.changedArticles.map((item) => item.entryId), ['7']);
    expect(result.unchangedArticles, hasLength(50));
  });

  test(
    'mixed inbox groups compensate an earlier group when the next fails',
    () async {
      final articles = [
        article(1),
        article(2),
        article(3, inbox: true),
        article(4, inbox: true),
      ];
      final groupCalls = <bool>[];

      final result = await BatchReadSyncService.transition(
        articles,
        targetIsRead: true,
        markRead: (_, {required isInbox}) async {
          groupCalls.add(isInbox);
          return !isInbox;
        },
        markUnread: (_) async => true,
      );

      expect(groupCalls, [false, true]);
      expect(result.operationSucceededIds, {'1', '2'});
      expect(result.compensationSucceededIds, {'1', '2'});
      expect(result.changedArticles, isEmpty);
    },
  );
}
