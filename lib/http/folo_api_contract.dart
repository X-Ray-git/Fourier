import '../models/feed.dart';

/// Typed boundary helpers mirroring the Folo client SDK contract audited at
/// @follow-app/client-sdk 0.3.95.
abstract final class FoloApiContract {
  static bool isApiUri(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host == 'api.folo.is' &&
      uri.port == 443 &&
      uri.userInfo.isEmpty;

  static String sessionCookie(String token) =>
      '__Secure-better-auth.session_token=$token';

  static List<FeedModel> parseFeedSubscriptions(Object? data) {
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item['feeds'] is Map)
        .map(FeedModel.fromJson)
        .toList(growable: false);
  }

  static FeedModel? parseCreatedFeed(
    Map<String, dynamic>? responseBody, {
    required String? customTitle,
    required String? category,
    required int view,
    required String fallbackUrl,
  }) {
    final rawFeed = responseBody?['feed'];
    if (rawFeed is! Map) return null;
    return FeedModel.fromSubscriptionMutation(
      Map<String, dynamic>.from(rawFeed),
      customTitle: customTitle,
      category: category,
      view: view,
      fallbackUrl: fallbackUrl,
    );
  }

  static Map<String, dynamic> createSubscriptionRequest({
    required String url,
    required int view,
    required String? title,
    required String? category,
  }) => {
    'type': 'feed',
    'url': url,
    'view': view,
    'title': title,
    'category': category,
    'isPrivate': false,
  };

  static Map<String, dynamic> updateSubscriptionRequest({
    required String feedId,
    required int view,
    required String? title,
    required String? category,
  }) => {'feedId': feedId, 'view': view, 'title': title, 'category': category};

  static Map<String, dynamic> deleteSubscriptionRequest(String feedId) => {
    'feedIdList': [feedId],
  };

  static Map<String, dynamic> entryListRequest({
    required int view,
    required int limit,
    required bool read,
    required bool withContent,
    String? publishedAfter,
  }) => {
    'read': read,
    'limit': limit,
    'view': view,
    'withContent': withContent,
    'publishedAfter': ?publishedAfter,
  };

  static Map<String, dynamic> inboxEntryListRequest({
    required String inboxId,
    required int limit,
    required bool read,
    String? publishedAfter,
  }) => {
    'inboxId': inboxId,
    'read': read,
    'limit': limit,
    'publishedAfter': ?publishedAfter,
  };

  static Map<String, dynamic> markReadRequest({
    required List<String> entryIds,
    required bool isInbox,
  }) => {'entryIds': entryIds, 'isInbox': isInbox};

  static Map<String, dynamic> markUnreadRequest({
    required String entryId,
    required bool isInbox,
  }) => {'entryId': entryId, 'isInbox': isInbox};

  static Map<String, dynamic> updateCategoryRequest({
    required List<String> feedIds,
    required String category,
  }) => {'feedIdList': feedIds, 'category': category};
}
