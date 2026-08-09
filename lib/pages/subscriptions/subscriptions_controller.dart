import 'package:get/get.dart';

import '../../http/init.dart';
import '../../models/feed.dart';
import '../../services/account_session_guard.dart';
import '../../services/account_service.dart';
import '../../services/article_state_notifier.dart';
import '../../services/content_cache_service.dart';
import '../../services/local_article_db_service.dart';
import '../../services/feed_silent_settings_service.dart';
import '../../services/subscription_catalog_service.dart';
import '../../utils/source_taxonomy.dart';
import '../../utils/storage.dart';

class SourceCategoryNode {
  final String name;
  final List<FeedModel> feeds;

  SourceCategoryNode({required this.name, required this.feeds});
}

class SourceViewNode {
  final int view;
  final String name;
  final List<SourceCategoryNode> categories;

  SourceViewNode({
    required this.view,
    required this.name,
    required this.categories,
  });

  int get sourceCount =>
      categories.fold(0, (sum, cat) => sum + cat.feeds.length);
  int get categoryCount => categories.length;
}

/// 订阅源控制器
class SubscriptionsController extends GetxController {
  final loadingState = Rx<LoadingState<List<SourceViewNode>>>(const Loading());
  final allFeeds = <FeedModel>[].obs;
  final searchQuery = ''.obs;
  final viewNodes = <SourceViewNode>[].obs;
  final expandedState = <String, bool>{}.obs;
  Worker? _catalogWorker;
  Worker? _accountWorker;
  Worker? _articleStateWorker;
  Worker? _silentSettingsWorker;

  @override
  void onInit() {
    super.onInit();
    _catalogWorker = ever(
      SubscriptionCatalogService.version,
      (_) => _applyFeeds(SubscriptionCatalogService.feeds),
    );
    _accountWorker = ever(
      AccountService.instance.accountRevision,
      (_) => loadData(),
    );
    refreshUnreadCounts();
    loadData();
    _articleStateWorker = ever(
      ArticleStateNotifier.version,
      (_) => refreshUnreadCounts(ArticleStateNotifier.lastEntryId),
    );
    _silentSettingsWorker = ever(FeedSilentSettingsService.version, (_) {
      refreshUnreadCounts();
      viewNodes.refresh();
    });
  }

  @override
  void onClose() {
    _catalogWorker?.dispose();
    _accountWorker?.dispose();
    _articleStateWorker?.dispose();
    _silentSettingsWorker?.dispose();
    super.onClose();
  }

  Future<void> loadData() async {
    final accountRevision = AccountSessionGuard.revision;
    refreshUnreadCounts();
    if (!AccountService.instance.isLoggedIn.value) {
      loadingState.value = const LoadError('请先在“设置”页配置 Folo Token');
      viewNodes.clear();
      return;
    }

    final cached = SubscriptionCatalogService.feeds.isNotEmpty
        ? SubscriptionCatalogService.feeds
        : ContentCacheService.readSubscriptions();
    if (cached.isNotEmpty) {
      _applyFeeds(cached);
    } else {
      loadingState.value = const Loading();
    }

    final result = await SubscriptionCatalogService.sync();
    if (!AccountSessionGuard.isCurrent(accountRevision)) return;
    if (result.feeds.isNotEmpty || result.anySucceeded) {
      _applyFeeds(result.feeds);
    } else if (cached.isEmpty) {
      loadingState.value = LoadError<List<SourceViewNode>>(
        result.subscriptionsError ?? result.inboxesError ?? '加载失败',
      );
    }
  }

  void _applyFeeds(List<FeedModel> feeds) {
    allFeeds.value = feeds;
    final nodes = _buildViewNodes(feeds);
    viewNodes.value = nodes;
    _syncExpandedState(nodes);
    loadingState.value = Success(nodes);
  }

  void updateSearchQuery(String value) {
    searchQuery.value = value.trim().toLowerCase();
  }

  /// 每源未读计数
  final _unreadCounts = <String, int>{}.obs;

  void refreshUnreadCounts([String? eid]) {
    if (eid != null) {
      final raw = GStorage.articleDb.get(eid);
      if (raw is Map) {
        final feedId = raw['feedId'] as String?;
        if (feedId != null && feedId.isNotEmpty) {
          int count = 0;
          for (final item in GStorage.articleDb.values) {
            if (item is Map) {
              if (item['feedId'] == feedId && item['isRead'] != true) {
                count++;
              }
            }
          }
          _unreadCounts[feedId] = count;
          _unreadCounts.refresh();
        }
      }
      return;
    }
    // 全量（首屏）
    final all = LocalArticleDbService.readAllArticles();
    final counts = <String, int>{};
    for (final a in all) {
      if (a.isRead || a.feedId.isEmpty) continue;
      counts[a.feedId] = (counts[a.feedId] ?? 0) + 1;
    }
    _unreadCounts.value = counts;
  }

  int unreadFor(String feedId) {
    final unread = _unreadCounts[feedId] ?? 0;
    if (FeedSilentSettingsService.isSilent(feedId)) return 0;
    return unread;
  }

  int rawUnreadFor(String feedId) => _unreadCounts[feedId] ?? 0;

  int unreadForCategory(String categoryName, List<FeedModel> feeds) {
    int total = 0;
    for (final f in feeds) {
      total += unreadFor(f.feedId);
    }
    return total;
  }

  int unreadForView(List<SourceCategoryNode> categories) {
    int total = 0;
    for (final cat in categories) {
      total += unreadForCategory(cat.name, cat.feeds);
    }
    return total;
  }

  List<FeedModel> get silentFeeds {
    final result = <FeedModel>[];
    for (final view in filteredNodes) {
      for (final cat in view.categories) {
        result.addAll(
          cat.feeds.where((f) => FeedSilentSettingsService.isSilent(f.feedId)),
        );
      }
    }
    return result;
  }

  List<SourceViewNode> get sidebarNodes {
    final result = <SourceViewNode>[];
    for (final view in filteredNodes) {
      final categories = <SourceCategoryNode>[];
      for (final cat in view.categories) {
        final feeds = cat.feeds
            .where((f) => !FeedSilentSettingsService.isSilent(f.feedId))
            .toList();
        if (feeds.isNotEmpty) {
          categories.add(SourceCategoryNode(name: cat.name, feeds: feeds));
        }
      }
      if (categories.isNotEmpty) {
        result.add(
          SourceViewNode(
            view: view.view,
            name: view.name,
            categories: categories,
          ),
        );
      }
    }
    return result;
  }

  List<SourceViewNode> get filteredNodes {
    final query = searchQuery.value;
    if (query.isEmpty) return viewNodes;

    final result = <SourceViewNode>[];
    for (final view in viewNodes) {
      final viewMatched =
          view.name.toLowerCase().contains(query) ||
          SourceTaxonomy.viewKeyFromInt(view.view).contains(query);
      if (viewMatched) {
        result.add(view);
        continue;
      }

      final categories = <SourceCategoryNode>[];
      for (final category in view.categories) {
        final catMatched = category.name.toLowerCase().contains(query);
        final feeds = category.feeds.where((feed) {
          final title = feed.title.toLowerCase();
          final url = (feed.url ?? '').toLowerCase();
          final feedCategory = (feed.category ?? '').toLowerCase();
          final feedView = feed.viewLabel.toLowerCase();
          return title.contains(query) ||
              url.contains(query) ||
              feedCategory.contains(query) ||
              feedView.contains(query);
        }).toList();

        if (catMatched) {
          categories.add(category);
        } else if (feeds.isNotEmpty) {
          categories.add(SourceCategoryNode(name: category.name, feeds: feeds));
        }
      }

      if (categories.isNotEmpty) {
        result.add(
          SourceViewNode(
            view: view.view,
            name: view.name,
            categories: categories,
          ),
        );
      }
    }

    return result;
  }

  List<SourceViewNode> _buildViewNodes(List<FeedModel> feeds) {
    final viewMap = <int, Map<String, List<FeedModel>>>{};
    for (final feed in feeds) {
      final view = feed.view ?? 0;
      final category = feed.displayCategory;
      viewMap.putIfAbsent(view, () => <String, List<FeedModel>>{});
      viewMap[view]!.putIfAbsent(category, () => []).add(feed);
    }

    final nodes =
        viewMap.entries
            .map(
              (viewEntry) => SourceViewNode(
                view: viewEntry.key,
                name: SourceTaxonomy.viewLabelFromInt(viewEntry.key),
                categories:
                    viewEntry.value.entries
                        .map(
                          (catEntry) => SourceCategoryNode(
                            name: catEntry.key,
                            feeds: catEntry.value..sort(_compareFeeds),
                          ),
                        )
                        .toList()
                      ..sort((a, b) => a.name.compareTo(b.name)),
              ),
            )
            .toList()
          ..sort(
            (a, b) => SourceTaxonomy.viewOrderFromInt(
              a.view,
            ).compareTo(SourceTaxonomy.viewOrderFromInt(b.view)),
          );
    return nodes;
  }

  int _compareFeeds(FeedModel a, FeedModel b) {
    final viewCmp = a.viewOrder.compareTo(b.viewOrder);
    if (viewCmp != 0) return viewCmp;
    final catCmp = a.displayCategory.compareTo(b.displayCategory);
    if (catCmp != 0) return catCmp;
    return a.title.compareTo(b.title);
  }

  bool isExpanded(String key, {bool defaultExpanded = false}) {
    return expandedState[key] ?? defaultExpanded;
  }

  void setExpanded(String key, bool expanded) {
    expandedState[key] = expanded;
  }

  void _syncExpandedState(List<SourceViewNode> nodes) {
    final allowed = <String>{'special:silent'};
    for (final view in nodes) {
      allowed.add('view:${view.name}');
      for (final category in view.categories) {
        allowed.add('cat:${view.name}:${category.name}');
      }
    }
    expandedState.removeWhere((key, value) => !allowed.contains(key));
  }
}
