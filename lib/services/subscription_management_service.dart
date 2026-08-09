import '../http/feed_http.dart';
import '../http/init.dart';
import '../models/feed.dart';
import 'subscription_catalog_service.dart';
import 'undo_service.dart';

class SubscriptionDraft {
  const SubscriptionDraft({
    required this.url,
    required this.view,
    this.title,
    this.category,
  });

  final String url;
  final int view;
  final String? title;
  final String? category;

  factory SubscriptionDraft.fromFeed(FeedModel feed) {
    return SubscriptionDraft(
      url: feed.url ?? '',
      view: feed.view ?? 0,
      title: feed.customTitle,
      category: feed.category,
    );
  }

  String? get normalizedTitle => _nullableText(title);
  String? get normalizedCategory => _nullableText(category);

  static String? _nullableText(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}

abstract final class SubscriptionManagementService {
  static FeedModel? findByUrl(String url) {
    final normalized = _normalizeUrl(url);
    if (normalized.isEmpty) return null;
    for (final feed in SubscriptionCatalogService.feeds) {
      if (_normalizeUrl(feed.url ?? '') == normalized) return feed;
    }
    return null;
  }

  static Future<LoadingState<FeedModel>> create(SubscriptionDraft draft) async {
    final url = draft.url.trim();
    final existing = findByUrl(url);
    if (existing != null) return Success(existing);

    final result = await FeedHttp.createSubscription(
      url: url,
      view: draft.view,
      title: draft.normalizedTitle,
      category: draft.normalizedCategory,
    );
    if (result is LoadError<FeedModel?>) {
      return LoadError(result.errMsg ?? '添加订阅失败');
    }
    if (result is! Success<FeedModel?>) {
      return const LoadError('添加订阅失败');
    }

    final returnedFeed = result.response;
    if (returnedFeed != null && returnedFeed.feedId.isNotEmpty) {
      SubscriptionCatalogService.upsertLocal(returnedFeed);
    }

    await SubscriptionCatalogService.sync();
    final feed =
        findByUrl(url) ??
        (returnedFeed?.feedId.isNotEmpty == true ? returnedFeed : null);
    if (feed == null) {
      return const LoadError('订阅已添加，但目录暂时未能刷新，请稍后手动同步');
    }
    return Success(feed);
  }

  static Future<LoadingState<FeedModel>> update(
    FeedModel feed,
    SubscriptionDraft draft, {
    bool refreshCatalog = true,
  }) async {
    if (feed.feedId.isEmpty) return const LoadError('订阅源标识为空');
    final result = await FeedHttp.updateSubscription(
      feedId: feed.feedId,
      view: draft.view,
      title: draft.normalizedTitle,
      category: draft.normalizedCategory,
    );
    if (result is LoadError<void>) {
      return LoadError(result.errMsg ?? '更新订阅失败');
    }
    if (result is! Success<void>) return const LoadError('更新订阅失败');

    final updated = feed.copyWith(
      view: draft.view,
      customTitle: draft.normalizedTitle,
      clearCustomTitle: draft.normalizedTitle == null,
      category: draft.normalizedCategory,
      clearCategory: draft.normalizedCategory == null,
    );
    SubscriptionCatalogService.upsertLocal(updated);
    if (refreshCatalog) await SubscriptionCatalogService.sync();
    FeedModel? catalogFeed;
    for (final item in SubscriptionCatalogService.feeds) {
      if (item.feedId == feed.feedId) {
        catalogFeed = item;
        break;
      }
    }
    return Success(catalogFeed ?? updated);
  }

  static Future<LoadingState<void>> unsubscribe(
    FeedModel feed, {
    bool recordUndo = true,
  }) async {
    if (feed.feedId.isEmpty) return const LoadError('订阅源标识为空');
    final result = await FeedHttp.deleteSubscription(feedId: feed.feedId);
    if (result is LoadError<void>) {
      return LoadError(result.errMsg ?? '取消订阅失败');
    }
    if (result is! Success<void>) return const LoadError('取消订阅失败');

    SubscriptionCatalogService.removeLocal(feed.feedId);
    await SubscriptionCatalogService.sync();

    if (recordUndo) {
      var currentFeed = feed;
      UndoService.recordCustom(
        actionName: '取消订阅',
        description: '取消订阅《${feed.title}》',
        targetLabel: feed.title,
        undo: () async {
          final restored = await create(
            SubscriptionDraft.fromFeed(currentFeed),
          );
          if (restored is! Success<FeedModel>) return false;
          currentFeed = restored.response;
          return true;
        },
        redo: () async {
          final removed = await unsubscribe(currentFeed, recordUndo: false);
          return removed is Success<void>;
        },
      );
    }
    return const Success(null);
  }

  static Future<LoadingState<int>> renameCategory({
    required List<FeedModel> feeds,
    required String newCategory,
  }) async {
    final normalizedCategory = SubscriptionDraft._nullableText(newCategory);
    if (normalizedCategory == null) return const LoadError('分类名称不能为空');
    final feedIds = feeds
        .map((feed) => feed.feedId)
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (feedIds.isEmpty) return const Success(0);

    final result = await FeedHttp.updateCategory(
      feedIds: feedIds,
      category: normalizedCategory,
    );
    if (result is LoadError<void>) {
      return LoadError(result.errMsg ?? '更新分类失败');
    }
    if (result is! Success<void>) return const LoadError('更新分类失败');

    for (final feed in feeds) {
      SubscriptionCatalogService.upsertLocal(
        feed.copyWith(category: normalizedCategory),
      );
    }
    await SubscriptionCatalogService.sync();
    return Success(feedIds.length);
  }

  static String _normalizeUrl(String raw) {
    final trimmed = raw.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return trimmed.toLowerCase();
    }
    final normalizedPath = uri.path == '/' ? '' : uri.path;
    return uri
        .replace(
          scheme: uri.scheme.toLowerCase(),
          host: uri.host.toLowerCase(),
          path: normalizedPath,
          fragment: '',
        )
        .toString();
  }
}
