import 'package:flutter_test/flutter_test.dart';

import 'package:fourier/http/folo_api_contract.dart';
import 'package:fourier/http/public_content_http.dart';

void main() {
  group('FoloApiContract authentication boundary', () {
    test('accepts only the production Folo API origin', () {
      expect(
        FoloApiContract.isApiUri(Uri.parse('https://api.folo.is/entries')),
        isTrue,
      );
      expect(
        FoloApiContract.isApiUri(Uri.parse('http://api.folo.is/entries')),
        isFalse,
      );
      expect(
        FoloApiContract.isApiUri(Uri.parse('https://api.folo.is:444/entries')),
        isFalse,
      );
      expect(
        FoloApiContract.isApiUri(
          Uri.parse('https://api.folo.is.example.com/entries'),
        ),
        isFalse,
      );
      expect(
        FoloApiContract.isApiUri(Uri.parse('https://example.com/article')),
        isFalse,
      );
      expect(FoloApiContract.isApiUri(Uri.parse('/entries')), isFalse);
    });

    test('builds only the official session cookie', () {
      expect(
        FoloApiContract.sessionCookie('token-value'),
        '__Secure-better-auth.session_token=token-value',
      );
    });

    test('public article client has no Folo credentials or identifiers', () {
      final headers = PublicContentHttp.dio.options.headers;

      expect(headers, isNot(contains('Cookie')));
      expect(headers, isNot(contains('Authorization')));
      expect(headers, isNot(contains('X-Client-Id')));
      expect(headers, isNot(contains('X-Session-Id')));
    });
  });

  group('FoloApiContract subscriptions', () {
    test('parses only feed subscriptions from the union response', () {
      final feeds = FoloApiContract.parseFeedSubscriptions([
        {
          'feedId': 'feed-1',
          'title': 'Custom title',
          'category': 'Tech',
          'view': 0,
          'feeds': {
            'id': 'feed-1',
            'title': 'Source title',
            'url': 'https://example.com/feed',
          },
        },
        {
          'inboxId': 'inbox-1',
          'feedId': 'inbox-feed',
          'inboxes': {'id': 'inbox-1', 'title': 'Inbox'},
        },
        {
          'listId': 'list-1',
          'feedId': 'list-feed',
          'lists': {'id': 'list-1', 'title': 'List'},
        },
      ]);

      expect(feeds, hasLength(1));
      expect(feeds.single.feedId, 'feed-1');
      expect(feeds.single.title, 'Custom title');
    });

    test('parses create response fields from the top level', () {
      final feed = FoloApiContract.parseCreatedFeed(
        {
          'code': 0,
          'feed': {
            'id': 'feed-2',
            'title': 'Created feed',
            'url': 'https://example.com/rss',
          },
          'list': null,
          'unread': <String, int>{},
        },
        customTitle: null,
        category: 'News',
        view: 0,
        fallbackUrl: 'https://example.com/rss',
      );

      expect(feed, isNotNull);
      expect(feed!.feedId, 'feed-2');
      expect(feed.title, 'Created feed');
    });

    test('uses the official list form when deleting a feed subscription', () {
      expect(FoloApiContract.deleteSubscriptionRequest('feed-1'), {
        'feedIdList': ['feed-1'],
      });
    });
  });

  group('FoloApiContract request payloads', () {
    test('inbox list uses only fields declared by the official SDK', () {
      expect(
        FoloApiContract.inboxEntryListRequest(
          inboxId: 'inbox-1',
          limit: 100,
          read: false,
          publishedAfter: '2026-01-01T00:00:00.000Z',
        ),
        {
          'inboxId': 'inbox-1',
          'read': false,
          'limit': 100,
          'publishedAfter': '2026-01-01T00:00:00.000Z',
        },
      );
    });

    test('mark unread preserves the inbox namespace', () {
      expect(
        FoloApiContract.markUnreadRequest(entryId: 'entry-1', isInbox: true),
        {'entryId': 'entry-1', 'isInbox': true},
      );
    });

    test('category update uses the official batch shape', () {
      expect(
        FoloApiContract.updateCategoryRequest(
          feedIds: ['feed-1', 'feed-2'],
          category: 'Renamed',
        ),
        {
          'feedIdList': ['feed-1', 'feed-2'],
          'category': 'Renamed',
        },
      );
    });
  });
}
