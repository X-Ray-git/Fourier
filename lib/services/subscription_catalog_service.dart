import 'package:get/get.dart';

import '../http/feed_http.dart';
import '../http/init.dart';
import '../models/feed.dart';
import 'account_session_guard.dart';
import 'content_cache_service.dart';

class SubscriptionCatalogSyncResult {
  final List<FeedModel> feeds;
  final bool subscriptionsSucceeded;
  final bool inboxesSucceeded;
  final String? subscriptionsError;
  final String? inboxesError;

  const SubscriptionCatalogSyncResult({
    required this.feeds,
    required this.subscriptionsSucceeded,
    required this.inboxesSucceeded,
    this.subscriptionsError,
    this.inboxesError,
  });

  bool get anySucceeded => subscriptionsSucceeded || inboxesSucceeded;
  bool get allFailed => !subscriptionsSucceeded && !inboxesSucceeded;
}

/// Shared authoritative catalog for the timeline feed map and source sidebar.
abstract final class SubscriptionCatalogService {
  static final version = 0.obs;
  static List<FeedModel> _feeds = ContentCacheService.readSubscriptions();
  static Future<SubscriptionCatalogSyncResult>? _syncInFlight;

  static List<FeedModel> get feeds => List.unmodifiable(_feeds);

  static void reset() {
    _feeds = const [];
    _syncInFlight = null;
    version.value++;
  }

  static void upsertLocal(FeedModel feed) {
    if (feed.feedId.isEmpty) return;
    final next = <FeedModel>[
      for (final current in _feeds)
        if (current.feedId != feed.feedId) current,
      feed,
    ]..sort(_compareFeeds);
    _replaceLocal(next);
  }

  static void removeLocal(String feedId) {
    if (feedId.isEmpty) return;
    final next = _feeds
        .where((feed) => feed.feedId != feedId)
        .toList(growable: false);
    if (next.length == _feeds.length) return;
    _replaceLocal(next);
  }

  static Future<SubscriptionCatalogSyncResult> sync() {
    final existing = _syncInFlight;
    if (existing != null) return existing;

    final future = _syncInternal();
    _syncInFlight = future;
    return future.whenComplete(() {
      if (identical(_syncInFlight, future)) _syncInFlight = null;
    });
  }

  static Future<SubscriptionCatalogSyncResult> _syncInternal() async {
    final accountRevision = AccountSessionGuard.revision;
    final cached = ContentCacheService.readSubscriptions();
    if (_feeds.isEmpty && cached.isNotEmpty) _feeds = cached;

    final results = await Future.wait([
      FeedHttp.getSubscriptions(),
      FeedHttp.getInboxes(),
    ]);
    if (!AccountSessionGuard.isCurrent(accountRevision)) {
      return const SubscriptionCatalogSyncResult(
        feeds: [],
        subscriptionsSucceeded: false,
        inboxesSucceeded: false,
      );
    }
    final subscriptionsResult = results[0];
    final inboxesResult = results[1];

    final freshSubscriptions = subscriptionsResult is Success<List<FeedModel>>
        ? subscriptionsResult.response
        : null;
    final freshInboxes = inboxesResult is Success<List<Map<String, dynamic>>>
        ? inboxesResult.response.map(FeedModel.fromInboxJson).toList()
        : null;

    final reconciled = reconcile(
      cached: cached,
      freshSubscriptions: freshSubscriptions,
      freshInboxes: freshInboxes,
    );
    _feeds = reconciled;
    if (freshSubscriptions != null || freshInboxes != null) {
      ContentCacheService.saveSubscriptions(reconciled);
    }
    version.value++;

    return SubscriptionCatalogSyncResult(
      feeds: feeds,
      subscriptionsSucceeded: freshSubscriptions != null,
      inboxesSucceeded: freshInboxes != null,
      subscriptionsError: subscriptionsResult is LoadError<List<FeedModel>>
          ? subscriptionsResult.errMsg
          : null,
      inboxesError: inboxesResult is LoadError<List<Map<String, dynamic>>>
          ? inboxesResult.errMsg
          : null,
    );
  }

  static List<FeedModel> reconcile({
    required List<FeedModel> cached,
    List<FeedModel>? freshSubscriptions,
    List<FeedModel>? freshInboxes,
  }) {
    final cachedSubscriptions = cached.where((feed) => !feed.isInbox);
    final cachedInboxes = cached.where((feed) => feed.isInbox);
    final combined = <FeedModel>[
      ...(freshSubscriptions ?? cachedSubscriptions),
      ...(freshInboxes ?? cachedInboxes),
    ];

    final byId = <String, FeedModel>{};
    for (final feed in combined) {
      if (feed.feedId.isNotEmpty) byId[feed.feedId] = feed;
    }
    return byId.values.toList()..sort(_compareFeeds);
  }

  static int _compareFeeds(FeedModel a, FeedModel b) {
    final viewCompare = a.viewOrder.compareTo(b.viewOrder);
    if (viewCompare != 0) return viewCompare;
    final categoryCompare = a.displayCategory.compareTo(b.displayCategory);
    if (categoryCompare != 0) return categoryCompare;
    return a.title.compareTo(b.title);
  }

  static void _replaceLocal(List<FeedModel> feeds) {
    _feeds = feeds;
    ContentCacheService.saveSubscriptions(_feeds);
    version.value++;
  }
}
