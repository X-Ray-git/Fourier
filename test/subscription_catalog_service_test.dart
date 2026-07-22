import 'package:autofolo/models/feed.dart';
import 'package:autofolo/services/subscription_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FeedModel feed(String id, {int view = 0, String? category}) =>
      FeedModel(feedId: id, title: 'Feed $id', view: view, category: category);

  test(
    'successful partitions replace cached subscriptions authoritatively',
    () {
      final result = SubscriptionCatalogService.reconcile(
        cached: [feed('removed'), feed('old-inbox', view: 2)],
        freshSubscriptions: [feed('added')],
        freshInboxes: [feed('new-inbox', view: 2)],
      );

      expect(result.map((item) => item.feedId).toSet(), {'added', 'new-inbox'});
    },
  );

  test('a failed partition keeps only that partition from cache', () {
    final result = SubscriptionCatalogService.reconcile(
      cached: [feed('old-feed'), feed('old-inbox', view: 2)],
      freshSubscriptions: [feed('new-feed')],
      freshInboxes: null,
    );

    expect(result.map((item) => item.feedId).toSet(), {
      'new-feed',
      'old-inbox',
    });
  });

  test('empty successful response removes the matching cached partition', () {
    final result = SubscriptionCatalogService.reconcile(
      cached: [feed('old-feed'), feed('old-inbox', view: 2)],
      freshSubscriptions: const [],
      freshInboxes: null,
    );

    expect(result.map((item) => item.feedId), ['old-inbox']);
  });
}
