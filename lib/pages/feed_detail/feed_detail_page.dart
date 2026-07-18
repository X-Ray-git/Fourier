import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../common/constants/constants.dart';
import '../../http/feed_http.dart';
import '../../http/init.dart';
import '../../models/article.dart';
import '../../models/feed.dart';
import '../../router/app_pages.dart';
import '../../utils/security_utils.dart';
import '../../utils/source_taxonomy.dart';
import '../../common/widgets/feedback_toast.dart';
import '../../common/widgets/app_glass.dart';
import '../../common/widgets/app_glass_selection_button.dart';
import '../../common/widgets/article_card_chrome.dart';
import '../../common/widgets/mobile_article_range_button.dart';
import '../../common/widgets/no_overscroll_indicator_behavior.dart';
import '../../common/widgets/refresh_indicator.dart' as custom_refresh;
import '../../common/widgets/shimmer_card.dart';
import '../../common/widgets/mac_empty_placeholder.dart';
import '../../common/widgets/mac_header_pane.dart';
import '../../services/account_service.dart';
import '../../services/article_image_service.dart';
import '../../services/content_cache_service.dart';
import '../../services/local_article_db_service.dart';
import '../../services/auto_readability_worker.dart';
import '../../services/article_state_notifier.dart';
import '../../services/read_sync_service.dart';
import '../../services/feed_silent_settings_service.dart';
import '../../services/feed_translation_settings_service.dart';
import '../../services/feed_readability_settings_service.dart';
import '../../services/undo_service.dart';
import '../../utils/storage.dart';
import '../widgets/article_card.dart';
import '../timeline/timeline_controller.dart';
import '../subscriptions/subscriptions_controller.dart';
import '../article/article_page.dart';
import '../../utils/scroll_utils.dart';

/// Feed 详情控制器 — 按订阅源或分类或 view 筛选文章
class FeedDetailController extends GetxController {
  final loadingState = Rx<LoadingState<List<ArticleModel>>>(const Loading());

  late final String feedTitle;
  late final String? filterFeedId;
  late final String? filterCategory;
  late final int? filterView;
  late final String? feedImage;
  late final String _cacheScope;
  final Map<String, FeedModel> _feedMap = {};
  bool _feedsLoaded = false;
  bool _isRefreshingRecentRead = false;

  final articles = <ArticleModel>[].obs;
  final isAutoTranslateEnabled = false.obs;
  final isAutoReadabilityEnabled = false.obs;
  final isSilentEnabled = false.obs;
  final readFilter = 0.obs; // 0=未读, 1=全部, 2=已读
  final allArticles = <ArticleModel>[].obs; // 全量（含已读）
  final selectedArticle = Rxn<ArticleModel>();
  final Map<String, GlobalKey> itemKeys = {};
  String? _lastArticleTapEntryId;
  DateTime? _lastArticleTapAt;

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments as Map<String, dynamic>;
    filterFeedId = args['feedId'] as String?;
    filterCategory = args['category'] as String?;
    filterView = args['view'] as int?;
    feedImage = args['feedImage'] as String?;
    feedTitle =
        (args['feedTitle'] as String?) ??
        (args['categoryName'] as String?) ??
        (args['viewName'] as String?) ??
        '';
    _cacheScope =
        filterFeedId ??
        'category:${filterCategory ?? 'view:${filterView ?? 'all'}'}';
    refreshAutoTranslateStatus();
    refreshAutoReadabilityStatus();
    refreshSilentStatus();
    loadData();
    ever(ArticleStateNotifier.version, (_) => _refreshFromLocal());
  }

  void _applyFilter() {
    switch (readFilter.value) {
      case 0:
        articles.value = allArticles
            .where((a) => !a.isRead && !a.isRejectedByAi)
            .toList();
      case 1:
        articles.value = allArticles.where((a) => !a.isRejectedByAi).toList();
      case 2:
        articles.value = allArticles
            .where((a) => a.isRead && !a.isRejectedByAi)
            .toList();
    }
  }

  void setReadFilter(int value, {bool clearSelection = false}) {
    if (readFilter.value == value && !clearSelection) return;
    readFilter.value = value;
    _applyFilter();
    if (clearSelection) {
      selectedArticle.value = null;
    }
  }

  void selectRelativeArticle(int delta) {
    if (articles.isEmpty) return;

    final selected = selectedArticle.value;
    final currentIndex = selected == null
        ? -1
        : articles.indexWhere((a) => a.entryId == selected.entryId);
    final nextIndex = (currentIndex + delta).clamp(0, articles.length - 1);
    if (nextIndex < 0 || nextIndex >= articles.length) return;
    selectedArticle.value = articles[nextIndex];
    scrollToArticle(articles[nextIndex].entryId);
  }

  void scrollToArticle(String entryId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = itemKeys[entryId];
      if (key != null && key.currentContext != null) {
        ScrollUtils.ensureVisible(key.currentContext!);
      }
    });
  }

  Future<void> openOriginalArticle(ArticleModel article) async {
    if (article.url.isEmpty) return;

    final uri = SecurityUtils.parseHttpUrl(article.url);
    if (uri == null) {
      AppFeedback.error('无法打开链接', '链接格式无效或协议不受支持');
      return;
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      AppFeedback.error('无法打开链接', '未找到默认浏览器');
    }
  }

  void handleMacArticleTap(ArticleModel article) {
    final now = DateTime.now();
    final isDoubleTap =
        _lastArticleTapEntryId == article.entryId &&
        _lastArticleTapAt != null &&
        now.difference(_lastArticleTapAt!).inMilliseconds < 300;

    selectedArticle.value = article;
    _lastArticleTapEntryId = article.entryId;
    _lastArticleTapAt = now;

    if (isDoubleTap) {
      _lastArticleTapEntryId = null;
      _lastArticleTapAt = null;
      selectRelativeArticle(1);
      openOriginalArticle(article);

      if (!article.isRead) {
        unawaited(UndoService.markAsRead(article, showSuccess: false));
      }
    }
  }

  void _refreshFromLocal() {
    final eid = ArticleStateNotifier.lastEntryId;
    if (eid == null) return;
    // 增量：读单篇
    final raw = GStorage.articleDb.get(eid);
    if (raw is! Map) return;
    final article = ArticleModel.fromCache(Map<String, dynamic>.from(raw));
    if (!_matchesScope(article)) return;

    final merged = _mergeLocalReadState([article]).first;
    // 同步更新 allArticles
    final ai = allArticles.indexWhere((a) => a.entryId == eid);
    if (ai >= 0) {
      allArticles[ai] = merged;
      allArticles.refresh();
    } else {
      allArticles.add(merged);
    }
    _applyFilter();
  }

  void refreshAutoTranslateStatus() {
    final feedId = filterFeedId;
    if (feedId == null || feedId.isEmpty) {
      isAutoTranslateEnabled.value = false;
      return;
    }
    isAutoTranslateEnabled.value =
        FeedTranslationSettingsService.isAutoTranslateEnabled(feedId);
  }

  void refreshSilentStatus() {
    final feedId = filterFeedId;
    if (feedId == null || feedId.isEmpty) {
      isSilentEnabled.value = false;
      return;
    }
    isSilentEnabled.value = FeedSilentSettingsService.isSilent(feedId);
  }

  void refreshAutoReadabilityStatus() {
    final feedId = filterFeedId;
    if (feedId == null || feedId.isEmpty) {
      isAutoReadabilityEnabled.value = false;
      return;
    }
    isAutoReadabilityEnabled.value =
        FeedReadabilitySettingsService.isAutoReadabilityEnabled(feedId);
  }

  Future<void> loadData() async {
    if (!AccountService.instance.isLoggedIn.value) {
      loadingState.value = const LoadError('请先在“设置”页配置 Folo Token');
      articles.clear();
      return;
    }

    unawaited(ReadSyncService.syncPendingReads());

    bool hasInitialContent = false;
    final local = LocalArticleDbService.readAllArticles()
        .where(_matchesScope)
        .toList();
    if (local.isNotEmpty) {
      allArticles.value = _mergeLocalReadState(local);
      _applyFilter();
      loadingState.value = Success(articles.toList());
      hasInitialContent = true;
    } else if (Get.isRegistered<TimelineController>()) {
      final timeline = Get.find<TimelineController>();
      if (timeline.loadingState.value is Success<List<ArticleModel>> &&
          timeline.allArticles.isNotEmpty) {
        allArticles.value = timeline.allArticles.where(_matchesScope).toList();
        _applyFilter();
        loadingState.value = Success(articles.toList());
        hasInitialContent = true;
      }
    }

    final cachedArticles = ContentCacheService.readFeedDetailArticles(
      _cacheScope,
    );
    if (!hasInitialContent && cachedArticles.isNotEmpty) {
      allArticles.value = _mergeLocalReadState(cachedArticles);
      _applyFilter();
      loadingState.value = Success(articles.toList());
      hasInitialContent = true;
    } else if (!hasInitialContent) {
      loadingState.value = const Loading();
    }

    if (!_feedsLoaded) {
      final cachedFeeds = ContentCacheService.readSubscriptions();
      final cachedInboxFeeds = cachedFeeds
          .where((feed) => feed.isInbox)
          .toList();
      for (final feed in cachedFeeds) {
        _feedMap[feed.feedId] = feed;
      }

      final needRefresh =
          _feedMap.isEmpty || !ContentCacheService.isSubscriptionsFresh();
      if (needRefresh) {
        final feedResult = await FeedHttp.getSubscriptions();
        if (feedResult is Success<List<FeedModel>>) {
          final merged = <FeedModel>[
            ...feedResult.response,
            ...cachedInboxFeeds,
          ];
          for (final f in merged) {
            _feedMap[f.feedId] = f;
          }
          ContentCacheService.saveSubscriptions(merged);
        }
      }
      _feedsLoaded = true;
    }

    final results = await Future.wait([
      FeedHttp.collectEntries(view: 0, withContent: true, feedMap: _feedMap),
      FeedHttp.collectEntries(view: 1, withContent: true, feedMap: _feedMap),
      FeedHttp.collectAllInboxEntries(limit: 100, withContent: true),
    ]);

    final unreadResult = results[0];
    final socialResult = results[1];
    final inboxResult = results[2];

    if (unreadResult is LoadError<List<ArticleModel>>) {
      if (!hasInitialContent && cachedArticles.isEmpty) {
        loadingState.value = unreadResult;
      }
      return;
    }

    final unreadData = unreadResult is Success<List<ArticleModel>>
        ? unreadResult.response
        : <ArticleModel>[];

    if (socialResult is Success<List<ArticleModel>>) {
      unreadData.addAll(socialResult.response);
    }

    if (inboxResult is Success<List<ArticleModel>>) {
      unreadData.addAll(inboxResult.response);
    }

    final filteredUnread = unreadData.where(_matchesScope).toList();
    final feedsOk = unreadResult is Success<List<ArticleModel>>;
    final socialOk = socialResult is Success<List<ArticleModel>>;
    final inboxOk = inboxResult is Success<List<ArticleModel>>;

    _applyUnreadSnapshot(
      filteredUnread,
      feedsOk: feedsOk,
      socialOk: socialOk,
      inboxOk: inboxOk,
    );

    final all = LocalArticleDbService.readAllArticles()
        .where(_matchesScope)
        .toList();
    allArticles.value = _mergeLocalReadState(all);
    _applyFilter();
    loadingState.value = Success(articles.toList());

    final unread = allArticles.where((a) => !a.isRead).toList();
    ContentCacheService.saveFeedDetailArticles(_cacheScope, unread);
    // 全量同步完成后，强制通知订阅列表做全量重新计数，保证数字一致
    if (Get.isRegistered<SubscriptionsController>()) {
      Get.find<SubscriptionsController>().refreshUnreadCounts();
    }
    unawaited(_refreshRecentReadWindow());
  }

  // Removed unused snapshot methods

  int get _readSyncWindowDays {
    final raw = GStorage.setting.get(
      StorageKeys.readSyncWindowDays,
      defaultValue: AppConstants.defaultReadSyncWindowDays,
    );
    if (raw is int && raw > 0) return raw;
    if (raw is String) {
      final parsed = int.tryParse(raw);
      if (parsed != null && parsed > 0) return parsed;
    }
    return AppConstants.defaultReadSyncWindowDays;
  }

  bool _matchesScope(ArticleModel article) {
    if (filterFeedId != null) {
      return article.feedId == filterFeedId;
    }
    if (filterCategory != null) {
      return article.subscriptionCategory == filterCategory;
    }
    if (filterView != null) {
      return article.category == SourceTaxonomy.viewKeyFromInt(filterView);
    }
    return true;
  }

  void _applyUnreadSnapshot(
    List<ArticleModel> unreadData, {
    bool feedsOk = true,
    bool socialOk = true,
    bool inboxOk = true,
  }) {
    final unreadIds = unreadData.map((a) => a.entryId).toSet();
    final localArticles = LocalArticleDbService.readAllArticles()
        .where(_matchesScope)
        .toList();

    for (final local in localArticles) {
      if (unreadIds.contains(local.entryId)) continue;

      // 按文章类型独立判定：对应 API 失败则跳过，不误标记
      if (local.category == 'inbox' && !inboxOk) continue;
      if (local.category == 'social' && !socialOk) continue;
      if (!feedsOk && local.category != 'inbox' && local.category != 'social') {
        continue;
      }

      final localOverride = LocalArticleDbService.readOverrideOf(local.entryId);
      if (localOverride != null) {
        // 服务端未读快照已不再包含该文，已读状态得到确认；
        // 本地“恢复未读”覆盖也在此时失效。
        GStorage.readStatus.delete(local.entryId);
      }
      // 只更新本地缓存，不创建 readStatus 覆盖（系统推断，非用户操作）
      LocalArticleDbService.setReadState(local.entryId, true);
    }

    // 未读请求可能早于 mark-read 请求发出，返回的仍是旧快照。
    // 本地已读覆盖必须保留到某次成功快照明确不再包含该文章。
    LocalArticleDbService.upsertMany(unreadData, defaultReadState: false);
    AutoReadabilityWorker.enqueueMany(unreadData);
  }

  Future<void> _refreshRecentReadWindow() async {
    if (_isRefreshingRecentRead || !AccountService.instance.isLoggedIn.value) {
      return;
    }
    _isRefreshingRecentRead = true;

    try {
      final windowStart = DateTime.now().subtract(
        Duration(days: _readSyncWindowDays),
      );
      final readResults = await Future.wait([
        FeedHttp.getEntries(
          view: 0,
          read: true,
          limit: 200,
          withContent: true,
          feedMap: _feedMap,
        ),
        FeedHttp.getEntries(
          view: 1,
          read: true,
          limit: 200,
          withContent: true,
          feedMap: _feedMap,
        ),
      ]);

      final feedsReadResult = readResults[0];
      final socialReadResult = readResults[1];

      final readData = <ArticleModel>[];
      if (feedsReadResult is Success<List<ArticleModel>>) {
        readData.addAll(feedsReadResult.response);
      }
      if (socialReadResult is Success<List<ArticleModel>>) {
        readData.addAll(socialReadResult.response);
      }

      // 本地按窗口过滤（不依赖 API 的 publishedAfter 参数语义）
      final windowedReadData = readData.where((a) {
        final pub = DateTime.tryParse(a.publishedAt);
        return pub != null && pub.isAfter(windowStart);
      }).toList();

      final scopedReadData = windowedReadData.where(_matchesScope).toList();
      if (scopedReadData.isEmpty) {
        AppFeedback.info('已同步已读', '最近$_readSyncWindowDays天没有新增已读文章');
        return;
      }

      LocalArticleDbService.upsertMany(scopedReadData, defaultReadState: true);
      final all = LocalArticleDbService.readAllArticles()
          .where(_matchesScope)
          .toList();
      allArticles.value = _mergeLocalReadState(all);
      _applyFilter();
      loadingState.value = Success(articles.toList());

      final unread = allArticles.where((a) => !a.isRead).toList();
      ContentCacheService.saveFeedDetailArticles(_cacheScope, unread);

      final earliest = scopedReadData
          .map((article) => DateTime.tryParse(article.publishedAt))
          .whereType<DateTime>()
          .toList();
      if (earliest.isNotEmpty) {
        earliest.sort();
        final timeText = DateFormat(
          'MM-dd HH:mm',
        ).format(earliest.first.toLocal());
        AppFeedback.success('已同步已读', '最早文章：$timeText');
      } else {
        AppFeedback.success('已同步已读', '最近$_readSyncWindowDays天已同步完成');
      }
    } finally {
      _isRefreshingRecentRead = false;
    }
  }

  List<ArticleModel> _mergeLocalReadState(List<ArticleModel> source) {
    return source.map((a) {
      final localRead = LocalArticleDbService.readOverrideOf(a.entryId);
      if (localRead != null && localRead != a.isRead) {
        return ArticleModel(
          entryId: a.entryId,
          feedId: a.feedId,
          feedTitle: a.feedTitle,
          feedImage: a.feedImage,
          title: a.title,
          url: a.url,
          content: a.content,
          publishedAt: a.publishedAt,
          isRead: localRead,
          category: a.category,
          subscriptionCategory: a.subscriptionCategory,
          author: a.author,
          imageUrl: a.imageUrl,
          isRejectedByAi: a.isRejectedByAi,
          filterReason: a.filterReason,
          filterReviewed: a.filterReviewed,
          filteredAt: a.filteredAt,
        );
      }
      return a;
    }).toList();
  }
}

/// Feed 详情页 (沉浸式重构版)
class FeedDetailPage extends StatelessWidget {
  const FeedDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(FeedDetailController());
    final cs = Theme.of(context).colorScheme;

    // 解析安全的头像链接
    final safeImageUrl =
        controller.feedImage != null && controller.feedImage!.isNotEmpty
        ? (ArticleImageService.toProxiedUrl(controller.feedImage) ??
              controller.feedImage)
        : null;

    if (Platform.isMacOS) {
      return _buildMacOSLayout(context, controller, cs, safeImageUrl);
    }

    return Scaffold(
      body: custom_refresh.RefreshIndicator(
        displacement: MediaQuery.paddingOf(context).top + kToolbarHeight + 10,
        onRefresh: controller.loadData,
        color: cs.primary,
        backgroundColor: cs.surfaceContainerHighest,
        child: CustomScrollView(
          physics: NoOverscrollIndicatorBehavior.applyMacosFlingCap(
            const AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverAppBar(
              pinned: true,
              toolbarHeight: 68,
              backgroundColor: cs.surface.withValues(alpha: 0.74),
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              iconTheme: IconThemeData(color: cs.onSurface),
              actionsIconTheme: IconThemeData(color: cs.onSurface),
              flexibleSpace: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: const SizedBox.expand(),
                ),
              ),
              titleSpacing: 0,
              title: Row(
                children: [
                  _MobileFeedAvatar(imageUrl: safeImageUrl),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          controller.feedTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Obx(() {
                          final unread = controller.articles
                              .where((article) => !article.isRead)
                              .length;
                          final total = controller.articles.length;
                          return Text(
                            unread > 0
                                ? '$unread 篇未读 · $total 篇当前列表'
                                : '$total 篇当前列表',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                Obx(
                  () => MobileArticleRangeButton(
                    unreadOnly: controller.readFilter.value == 0,
                    onChanged: (unreadOnly) => controller.setReadFilter(
                      unreadOnly ? 0 : 1,
                      clearSelection: true,
                    ),
                  ),
                ),
                if (controller.filterFeedId != null) ...[
                  const SizedBox(width: 6),
                  AppGlassIconButton(
                    icon: Icons.tune_rounded,
                    tooltip: '订阅源设置',
                    size: 36,
                    iconSize: 19,
                    onPressed: () =>
                        _showMobileFeedSettings(context, controller),
                  ),
                ],
                const SizedBox(width: 10),
              ],
            ),

            // ─── 文章列表区域 ───
            Obx(() {
              final state = controller.loadingState.value;

              return switch (state) {
                Loading() => const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _FeedDetailSkeleton(),
                ),
                LoadError(:final errMsg) => SliverFillRemaining(
                  hasScrollBody: false,
                  child: _ErrorView(
                    message: errMsg,
                    onRetry: controller.loadData,
                  ),
                ),
                Success(:final response) when response.isEmpty =>
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyView(
                      onRetry: controller.loadData,
                      readFilter: controller.readFilter.value,
                    ),
                  ),
                Success() => Obx(() {
                  final list = controller.articles;
                  if (list.isEmpty) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyView(
                        onRetry: controller.loadData,
                        readFilter: controller.readFilter.value,
                      ),
                    );
                  }
                  return SliverPadding(
                    padding: EdgeInsets.only(
                      top: 6,
                      bottom: 16 + MediaQuery.of(context).padding.bottom,
                    ),
                    sliver: SliverList.builder(
                      itemCount: list.length,
                      itemBuilder: (context, index) {
                        final article = list[index];
                        return ArticleCard(
                          article: article,
                          showFeedTitle: true,
                          onTap: () {
                            Get.toNamed(
                              Routes.article,
                              arguments: {
                                'article': article,
                                'sequence': controller.articles.toList(),
                                'index': index,
                              },
                            );
                          },
                        );
                      },
                    ),
                  );
                }),
              };
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _showMobileFeedSettings(
    BuildContext context,
    FeedDetailController controller,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.30),
      builder: (sheetContext) =>
          _MobileFeedSettingsSheet(controller: controller),
    );
  }

  Widget _buildMacOSLayout(
    BuildContext context,
    FeedDetailController controller,
    ColorScheme cs,
    String? safeImageUrl,
  ) {
    return ColoredBox(
      color: cs.surface,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 380,
            child: MacHeaderPane(
              headerHeight: 68,
              header: _MacFeedHeader(
                controller: controller,
                colorScheme: cs,
                imageUrl: safeImageUrl,
              ),
              body: _MacFeedArticleList(controller: controller),
            ),
          ),
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: cs.outlineVariant.withValues(alpha: 0.35),
          ),
          Expanded(
            child: Obx(() {
              final selected = controller.selectedArticle.value;
              if (selected == null) {
                return const MacSplitDetailEmptyPlaceholder(topInset: 69);
              }
              return ArticlePageView(
                key: ValueKey(selected.entryId),
                article: selected,
                isSplitView: true,
                isSelectedArticle: (entryId) =>
                    controller.selectedArticle.value?.entryId == entryId,
                onClose: () => controller.selectedArticle.value = null,
                onPrevious: () => controller.selectRelativeArticle(-1),
                onNext: () => controller.selectRelativeArticle(1),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _MacFeedHeader extends StatelessWidget {
  final FeedDetailController controller;
  final ColorScheme colorScheme;
  final String? imageUrl;

  const _MacFeedHeader({
    required this.controller,
    required this.colorScheme,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 68,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(74, 8, 8, 8),
        child: Row(
          children: [
            AppGlassIconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              tooltip: '返回',
              onPressed: Get.back,
              useOwnLayer: false,
            ),
            const SizedBox(width: 4),
            _MacFeedAvatar(imageUrl: imageUrl, colorScheme: colorScheme),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    controller.feedTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Obx(() {
                    final unread = controller.articles
                        .where((a) => !a.isRead)
                        .length;
                    final total = controller.articles.length;
                    return Text(
                      unread > 0
                          ? '$unread 篇未读 · $total 篇当前列表'
                          : '$total 篇当前列表',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    );
                  }),
                ],
              ),
            ),
            _MacFeedReadFilterToggle(controller: controller),
            AppGlassIconButton(
              icon: Icons.sync,
              tooltip: '同步',
              onPressed: controller.loadData,
              useOwnLayer: false,
            ),
            if (controller.filterFeedId != null)
              Obx(() {
                final isEnabled = controller.isAutoReadabilityEnabled.value;
                return AppGlassIconButton(
                  icon: isEnabled ? Icons.article : Icons.article_outlined,
                  tooltip: isEnabled ? '自动拉取全文已开启' : '自动拉取全文',
                  selected: isEnabled,
                  useOwnLayer: false,
                  onPressed: () async {
                    await FeedReadabilitySettingsService.toggleAutoReadability(
                      controller.filterFeedId ?? '',
                    );
                    controller.refreshAutoReadabilityStatus();
                  },
                );
              }),
            if (controller.filterFeedId != null)
              Obx(() {
                final isEnabled = controller.isAutoTranslateEnabled.value;
                return AppGlassIconButton(
                  icon: isEnabled ? Icons.translate : Icons.translate_outlined,
                  tooltip: isEnabled ? '自动翻译已开启' : '自动翻译',
                  selected: isEnabled,
                  useOwnLayer: false,
                  onPressed: () async {
                    await FeedTranslationSettingsService.toggleAutoTranslate(
                      controller.filterFeedId ?? '',
                    );
                    controller.refreshAutoTranslateStatus();
                  },
                );
              }),
            if (controller.filterFeedId != null)
              Obx(() {
                final isEnabled = controller.isSilentEnabled.value;
                return AppGlassIconButton(
                  icon: isEnabled
                      ? Icons.notifications_off
                      : Icons.notifications_off_outlined,
                  tooltip: isEnabled ? '已开启静默' : '设为静默',
                  selected: isEnabled,
                  useOwnLayer: false,
                  onPressed: () async {
                    await FeedSilentSettingsService.toggleSilent(
                      controller.filterFeedId ?? '',
                    );
                    controller.refreshSilentStatus();
                  },
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _MacFeedReadFilterToggle extends StatefulWidget {
  final FeedDetailController controller;

  const _MacFeedReadFilterToggle({required this.controller});

  @override
  State<_MacFeedReadFilterToggle> createState() =>
      _MacFeedReadFilterToggleState();
}

class _MacFeedReadFilterToggleState extends State<_MacFeedReadFilterToggle> {
  static const _options = [
    AppGlassSelectionOption(
      value: 0,
      label: '未读',
      icon: Icons.filter_alt_rounded,
    ),
    AppGlassSelectionOption(
      value: 1,
      label: '全部',
      icon: Icons.filter_alt_off_rounded,
    ),
  ];

  int? _visualFilter;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final filter = _visualFilter ?? widget.controller.readFilter.value;
      final isUnread = filter == 0;
      final theme = Theme.of(context);

      return AppGlassMorphSelectionButton<int>(
        value: isUnread ? 0 : 1,
        options: _options,
        title: '文章范围',
        titleIcon: Icons.filter_alt_rounded,
        tooltip: isUnread ? '范围：未读' : '范围：全部',
        active: isUnread,
        useOwnLayer: false,
        triggerForegroundColor: theme.brightness == Brightness.dark
            ? Colors.white
            : theme.colorScheme.onSurface,
        onChanged: _setFilter,
      );
    });
  }

  void _setFilter(int filter) {
    _visualFilter = filter;
    widget.controller.setReadFilter(filter, clearSelection: true);
    Future.delayed(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      setState(() => _visualFilter = null);
    });
  }
}

class _MobileFeedAvatar extends StatelessWidget {
  final String? imageUrl;

  const _MobileFeedAvatar({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipOval(
      child: Container(
        width: 36,
        height: 36,
        color: cs.primaryContainer.withValues(alpha: 0.45),
        child: imageUrl == null
            ? Icon(Icons.rss_feed_rounded, size: 19, color: cs.primary)
            : CachedNetworkImage(
                imageUrl: imageUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) =>
                    Icon(Icons.rss_feed_rounded, size: 19, color: cs.primary),
              ),
      ),
    );
  }
}

class _MobileFeedSettingsSheet extends StatelessWidget {
  final FeedDetailController controller;

  const _MobileFeedSettingsSheet({required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppMobileGlassSheet(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Row(
            children: [
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '订阅源设置',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: Navigator.of(context).pop,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          Obx(
            () => _MobileFeedSettingTile(
              icon: Icons.chrome_reader_mode_outlined,
              title: '自动拉取全文',
              subtitle: '下次同步时对当前订阅源应用',
              value: controller.isAutoReadabilityEnabled.value,
              onChanged: () async {
                await FeedReadabilitySettingsService.toggleAutoReadability(
                  controller.filterFeedId ?? '',
                );
                controller.refreshAutoReadabilityStatus();
              },
            ),
          ),
          Obx(
            () => _MobileFeedSettingTile(
              icon: Icons.translate_rounded,
              title: '自动翻译',
              subtitle: '仅对当前订阅源生效',
              value: controller.isAutoTranslateEnabled.value,
              onChanged: () async {
                await FeedTranslationSettingsService.toggleAutoTranslate(
                  controller.filterFeedId ?? '',
                );
                controller.refreshAutoTranslateStatus();
              },
            ),
          ),
          Obx(
            () => _MobileFeedSettingTile(
              icon: Icons.notifications_off_outlined,
              title: '静默订阅源',
              subtitle: '从原分类列表中隔离',
              value: controller.isSilentEnabled.value,
              danger: controller.isSilentEnabled.value,
              onChanged: () async {
                await FeedSilentSettingsService.toggleSilent(
                  controller.filterFeedId ?? '',
                );
                controller.refreshSilentStatus();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileFeedSettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool danger;
  final Future<void> Function() onChanged;

  const _MobileFeedSettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeColor = danger ? cs.error : cs.primary;
    return ListTile(
      minTileHeight: 60,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Icon(icon, color: value ? activeColor : cs.onSurfaceVariant),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: Switch.adaptive(
        value: value,
        activeTrackColor: activeColor,
        onChanged: (_) => onChanged(),
      ),
      onTap: onChanged,
    );
  }
}

class _MacFeedAvatar extends StatelessWidget {
  final String? imageUrl;
  final ColorScheme colorScheme;

  const _MacFeedAvatar({required this.imageUrl, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Container(
        width: 38,
        height: 38,
        color: colorScheme.primaryContainer.withValues(alpha: 0.45),
        child: imageUrl == null
            ? Icon(Icons.rss_feed, size: 20, color: colorScheme.primary)
            : CachedNetworkImage(
                imageUrl: imageUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) =>
                    Icon(Icons.rss_feed, size: 20, color: colorScheme.primary),
              ),
      ),
    );
  }
}

class _MacFeedArticleList extends StatelessWidget {
  final FeedDetailController controller;

  const _MacFeedArticleList({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final state = controller.loadingState.value;
      return switch (state) {
        Loading() => const _FeedDetailSkeleton(),
        LoadError(:final errMsg) => _ErrorView(
          message: errMsg,
          onRetry: controller.loadData,
        ),
        Success() => Obx(() {
          final list = controller.articles;
          if (list.isEmpty) {
            return _EmptyView(
              onRetry: controller.loadData,
              readFilter: controller.readFilter.value,
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 18),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final article = list[index];
              return Obx(() {
                return ArticleCard(
                  key: controller.itemKeys.putIfAbsent(
                    article.entryId,
                    () => GlobalKey(),
                  ),
                  article: article,
                  showFeedTitle: true,
                  isSelected:
                      controller.selectedArticle.value?.entryId ==
                      article.entryId,
                  onTap: () => controller.handleMacArticleTap(article),
                );
              });
            },
          );
        }),
      };
    });
  }
}

// ─── 优雅的局部状态视图 ───

class _FeedDetailSkeleton extends StatelessWidget {
  const _FeedDetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return ShimmerFadeList(
      itemCount: 4,
      itemBuilder: (context, index) => Padding(
        padding: ArticleCardChrome.outerPadding,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: ArticleCardChrome.fillColor(context, selected: false),
            borderRadius: BorderRadius.circular(ArticleCardChrome.radius),
            border: Border.fromBorderSide(
              ArticleCardChrome.borderSide(context, selected: false),
            ),
          ),
          child: Padding(
            padding: ArticleCardChrome.contentPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: MediaQuery.of(context).size.width * 0.6,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 64,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;

  const _ErrorView({this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 44,
              color: colorScheme.error.withValues(alpha: 0.72),
            ),
            const SizedBox(height: 16),
            Text(
              '数据加载异常',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message ?? '请检查网络连接后重试',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重新加载'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final VoidCallback? onRetry;
  final int readFilter;

  const _EmptyView({this.onRetry, required this.readFilter});

  @override
  Widget build(BuildContext context) {
    if (Platform.isMacOS) {
      final isUnread = readFilter == 0;
      return MacEmptyPlaceholder(
        icon: isUnread ? Icons.done_all_rounded : Icons.inbox_outlined,
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final isUnread = readFilter == 0;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isUnread ? Icons.done_all_rounded : Icons.inbox_outlined,
              size: 44,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.58),
            ),
            const SizedBox(height: 16),
            Text(
              isUnread ? '全部读完啦' : '暂无文章',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isUnread ? '该订阅源暂无最新的未读文章\n你可以尝试下拉刷新获取最新内容' : '该分类下暂时没有符合条件的文章',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('刷新'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
