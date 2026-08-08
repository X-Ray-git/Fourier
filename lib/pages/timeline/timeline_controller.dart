import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';
import '../../common/widgets/app_badger.dart';

import '../../common/constants/constants.dart';
import '../../http/feed_http.dart';
import '../../http/init.dart';
import '../../models/article.dart';
import '../../models/feed.dart';
import '../../common/widgets/feedback_toast.dart';
import '../../services/account_session_guard.dart';
import '../../services/account_service.dart';
import '../../services/article_image_cache_service.dart';
import '../../services/content_cache_service.dart';
import '../../services/feed_silent_settings_service.dart';
import '../../services/local_article_db_service.dart';
import '../../services/auto_readability_worker.dart';
import '../../services/article_state_notifier.dart';
import '../../services/read_sync_service.dart';
import '../../services/subscription_catalog_service.dart';
import '../../utils/storage.dart';
import '../../utils/article_length_estimator.dart';
import '../subscriptions/subscriptions_controller.dart';

enum TimelineViewMode { unread, all, read }

enum TimelineSortMode { newest, longest, shortest }

/// 时间线控制器 — 本地文章库（未读/全部/已读）
class TimelineController extends GetxController {
  static const bool _animationProbeRequested = bool.fromEnvironment(
    'FOURIER_ANIMATION_PROBE',
  );

  final loadingState = Rx<LoadingState<List<ArticleModel>>>(const Loading());
  final articles = <ArticleModel>[].obs;
  final allArticles = <ArticleModel>[].obs;
  final selectedMode = TimelineViewMode.unread.obs;
  final selectedSortMode = TimelineSortMode.newest.obs;
  final selectedArticle = Rxn<ArticleModel>();
  final selectedFeedId = RxnString();
  final selectedCategory = RxnString();
  final filterCount = 0.obs;
  final isSyncing = false.obs;
  final isSilentSelected = false.obs;

  String? _cursor;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _isRefreshingRecentRead = false;
  bool _isBatchingScopeChange = false;
  bool _reloadAfterAccountChange = false;
  int _timelineListResetVersion = 0;
  String _timelineScopeKey = 'normal::';
  final Map<String, Object> _deferredReadVisualUpdates = {};
  final Map<String, Object> _deferredArticleStateNotifications = {};
  final Map<String, Timer> _deferredArticleStateNotificationFallbacks = {};
  final Set<String> _probeLocallyReadIds = {};
  final Set<String> _probeReportedReappearedIds = {};

  final Map<String, FeedModel> _feedMap = {};
  Future<void> Function()? _scrollToTopHandler;
  Worker? _accountWorker;

  @override
  void onInit() {
    super.onInit();
    ever(allArticles, (_) => _updateAppBadge());
    ever(selectedFeedId, (_) => _handleScopeFieldChanged());
    ever(selectedCategory, (_) => _handleScopeFieldChanged());
    ever(isSilentSelected, (_) => _handleScopeFieldChanged());
    _accountWorker = ever(
      AccountService.instance.accountRevision,
      (_) => _handleAccountChanged(),
    );

    // 监听全局文章状态变更，精准更新内存数据，保持 UI 同步（如 AI 过滤拦截数）
    ever(ArticleStateNotifier.version, (_) {
      final entryId = ArticleStateNotifier.lastEntryId;
      if (entryId != null) {
        _syncSingleArticleFromDb(entryId);
      }
    });

    loadFeedsThenArticles(showToast: false);
  }

  void _handleAccountChanged() {
    _cursor = null;
    _hasMore = false;
    _feedMap.clear();
    articles.clear();
    allArticles.clear();
    selectedArticle.value = null;
    selectedFeedId.value = null;
    selectedCategory.value = null;
    isSilentSelected.value = false;
    filterCount.value = 0;
    if (!AccountService.instance.isLoggedIn.value) {
      loadingState.value = const LoadError('请先在“设置”页登录 Folo');
      return;
    }
    if (isSyncing.value) {
      _reloadAfterAccountChange = true;
    } else {
      unawaited(loadFeedsThenArticles(showToast: false));
    }
  }

  /// 先加载订阅源映射，再加载文章
  Future<void> loadFeedsThenArticles({bool showToast = true}) async {
    if (isSyncing.value) {
      if (showToast) AppFeedback.info('请稍后', '同步正在进行中');
      return;
    }

    if (!AccountService.instance.isLoggedIn.value) {
      articles.clear();
      loadingState.value = const LoadError('请先在"设置"页配置 Folo Token');
      return;
    }

    final accountRevision = AccountSessionGuard.revision;
    isSyncing.value = true;
    try {
      final catalogResult = await SubscriptionCatalogService.sync();
      if (!AccountSessionGuard.isCurrent(accountRevision)) return;
      _feedMap
        ..clear()
        ..addEntries(
          catalogResult.feeds.map((feed) => MapEntry(feed.feedId, feed)),
        );

      final dataFuture = loadData();
      final minDuration = Future<void>.delayed(
        const Duration(milliseconds: 450),
      );
      await Future.wait([dataFuture, minDuration]);

      if (showToast) {
        final count = unreadCount;
        AppFeedback.success('已刷新', '$count 篇未读');
      }
    } finally {
      isSyncing.value = false;
      if (_reloadAfterAccountChange) {
        _reloadAfterAccountChange = false;
        unawaited(loadFeedsThenArticles(showToast: false));
      }
    }
  }

  Future<void> loadData() async {
    final accountRevision = AccountSessionGuard.revision;
    _cursor = null;
    _hasMore = false;

    unawaited(ReadSyncService.syncPendingReads());
    _loadFromLocalDatabase(resetReason: 'loadData.localCache');
    if (allArticles.isEmpty) {
      loadingState.value = const Loading();
    }

    final results = await Future.wait([
      FeedHttp.collectEntries(view: 0, withContent: true, feedMap: _feedMap),
      FeedHttp.collectEntries(view: 1, withContent: true, feedMap: _feedMap),
      FeedHttp.collectAllInboxEntries(limit: 100, withContent: true),
    ]);
    if (!AccountSessionGuard.isCurrent(accountRevision)) return;

    final feedsResult = results[0];
    final socialResult = results[1];
    final inboxResult = results[2];

    final unreadData = <ArticleModel>[];
    bool hasError = false;

    if (feedsResult is Success<List<ArticleModel>>) {
      unreadData.addAll(feedsResult.response);
    } else if (feedsResult is LoadError<List<ArticleModel>>) {
      hasError = true;
      if (allArticles.isEmpty) loadingState.value = feedsResult;
    }

    if (socialResult is Success<List<ArticleModel>>) {
      unreadData.addAll(socialResult.response);
    } else if (socialResult is LoadError<List<ArticleModel>>) {
      hasError = true;
    }

    if (inboxResult is Success<List<ArticleModel>>) {
      unreadData.addAll(inboxResult.response);
    } else if (inboxResult is LoadError<List<ArticleModel>>) {
      hasError = true;
    }

    if (hasError && allArticles.isNotEmpty) {
      AppFeedback.error('同步未完成', '部分未读数据拉取失败，请稍后重试');
    }

    final feedsOk = feedsResult is Success<List<ArticleModel>>;
    final socialOk = socialResult is Success<List<ArticleModel>>;
    final inboxOk = inboxResult is Success<List<ArticleModel>>;

    _applyUnreadSnapshot(
      unreadData,
      feedsOk: feedsOk,
      socialOk: socialOk,
      inboxOk: inboxOk,
    );
    _loadFromLocalDatabase(resetReason: 'loadData.unreadSnapshot');

    loadingState.value = Success(articles.toList());
    unawaited(
      _refreshArticleImageCache(LocalArticleDbService.readAllArticles()),
    );
    // 全量同步完成后，强制通知订阅列表做全量重新计数
    if (Get.isRegistered<SubscriptionsController>()) {
      Get.find<SubscriptionsController>().refreshUnreadCounts();
    }
    unawaited(_refreshRecentReadWindow());
  }

  Future<void> _refreshArticleImageCache(List<ArticleModel> articles) async {
    try {
      // refresh also reconciles expired read-image cleanup. Finish it before
      // re-enqueuing persisted failures so cleanup and retries cannot race.
      await ArticleImageCacheService.refresh(articles);
      await ArticleImageCacheService.retryFailedPrefetches();
    } catch (_) {
      // Image prefetch is best-effort and must not fail the timeline refresh.
    }
  }

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

  void _applyUnreadSnapshot(
    List<ArticleModel> unreadData, {
    bool feedsOk = true,
    bool socialOk = true,
    bool inboxOk = true,
  }) {
    final unreadIds = unreadData.map((a) => a.entryId).toSet();
    final localArticles = LocalArticleDbService.readAllArticles();

    for (final local in localArticles) {
      if (unreadIds.contains(local.entryId)) continue;

      // 按文章类型独立判定：对应 API 失败则跳过，不误标记
      if (local.category == 'inbox' && !inboxOk) continue;
      if (local.category == 'social' && !socialOk) continue;
      // feeds 文章：feeds API 是主数据源，失败则跳过
      if (!feedsOk && local.category != 'inbox' && local.category != 'social') {
        continue;
      }

      final localOverride = LocalArticleDbService.readOverrideOf(local.entryId);
      if (localOverride != null) {
        if (localOverride) {
          _logReadStateProbe(local.entryId, 'snapshot.confirms-local-read');
          _probeLocallyReadIds.remove(local.entryId);
          _probeReportedReappearedIds.remove(local.entryId);
        }
        // 服务端未读快照已不再包含该文，已读状态得到确认；
        // 本地“恢复未读”覆盖也在此时失效。
        GStorage.readStatus.delete(local.entryId);
      }
      // 只更新本地缓存，不创建 readStatus 覆盖（系统推断，非用户操作）
      LocalArticleDbService.setReadState(local.entryId, true);
    }

    // 未读请求可能早于 mark-read 请求发出，返回的仍是旧快照。
    // 本地已读覆盖必须保留到某次成功快照明确不再包含该文章。
    if (_animationProbeRequested && kDebugMode && Platform.isMacOS) {
      for (final article in unreadData) {
        if (_probeLocallyReadIds.contains(article.entryId) &&
            GStorage.readStatus.get(article.entryId) != true) {
          _logReadStateProbe(
            article.entryId,
            'snapshot.missing-local-read-override',
          );
        }
      }
    }

    LocalArticleDbService.upsertMany(unreadData, defaultReadState: false);
    AutoReadabilityWorker.enqueueMany(unreadData);
    ContentCacheService.saveTimelineArticles(unreadData);
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

      if (windowedReadData.isEmpty) {
        AppFeedback.info('已同步已读', '最近$_readSyncWindowDays天没有新增已读文章');
        return;
      }

      LocalArticleDbService.upsertMany(
        windowedReadData,
        defaultReadState: true,
      );
      _loadFromLocalDatabase(resetReason: 'recentRead.backfill');

      final earliest = windowedReadData
          .map(_timeScore)
          .whereType<int>()
          .fold<int?>(
            null,
            (min, value) => min == null || value < min ? value : min,
          );
      if (earliest != null && earliest > 0) {
        final timeText = DateFormat(
          'MM-dd HH:mm',
        ).format(DateTime.fromMillisecondsSinceEpoch(earliest).toLocal());
        AppFeedback.success('已同步已读', '最早文章：$timeText');
      } else {
        AppFeedback.success('已同步已读', '最近$_readSyncWindowDays天已同步完成');
      }
    } finally {
      _isRefreshingRecentRead = false;
    }
  }

  int? _timeScore(ArticleModel article) {
    final raw = article.publishedAt.trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.millisecondsSinceEpoch;
  }

  /// 加载更多（游标翻页）
  Future<void> loadMore() async {
    if (_isLoadingMore || !hasMore) return;
    _isLoadingMore = true;

    final result = await FeedHttp.getEntries(
      view: 0,
      withContent: true,
      publishedAfter: _cursor,
      feedMap: _feedMap,
    );

    if (result is Success<List<ArticleModel>>) {
      final data = result.response;
      if (data.isNotEmpty) {
        _cursor = data.last.publishedAt;
        LocalArticleDbService.upsertMany(_mergeLocalReadState(data));
        _loadFromLocalDatabase(resetReason: 'pagination.loadMore');
      }
      _hasMore = data.length >= 50;
    }

    _isLoadingMore = false;
  }

  void setViewMode(TimelineViewMode mode) {
    if (selectedMode.value == mode) return;
    resetTimelineListAnimation(reason: 'viewMode.change');
    selectedMode.value = mode;
    _applyFilter();
    loadingState.value = Success(articles.toList());
  }

  void setSortMode(TimelineSortMode mode) {
    if (selectedSortMode.value == mode) return;
    resetTimelineListAnimation(reason: 'sortMode.change');
    selectedSortMode.value = mode;
    _applyFilter();
    loadingState.value = Success(articles.toList());
  }

  /// 标记文章为已读（仅本地）
  void markAsReadLocal(
    String entryId, {
    bool recordHistory = true,
    bool deferVisualUpdateToFrameBoundary = false,
    bool deferArticleStateNotification = false,
  }) {
    if (entryId.trim().isEmpty) return;
    GStorage.readStatus.put(entryId, true);
    LocalArticleDbService.setReadState(
      entryId,
      true,
      recordHistory: recordHistory,
    );
    if (_animationProbeRequested && kDebugMode && Platform.isMacOS) {
      _probeLocallyReadIds.add(entryId);
      _probeReportedReappearedIds.remove(entryId);
      _logReadStateProbe(entryId, 'local.mark-read');
    }

    void updateVisualState() {
      final stopwatch = _animationProbeRequested
          ? (Stopwatch()..start())
          : null;
      _updateReadStateInMemory(
        entryId,
        true,
        updateSelectedArticle: !deferArticleStateNotification,
        useIncrementalUnreadRemoval: deferArticleStateNotification,
      );
      if (stopwatch != null) {
        _logReadStateProbe(
          entryId,
          'visual.update-complete-${stopwatch.elapsedMicroseconds}us',
        );
      }
      if (deferArticleStateNotification) {
        _deferArticleStateNotification(entryId);
      } else {
        _cancelDeferredArticleStateNotification(entryId);
        ArticleStateNotifier.tick(entryId);
      }
    }

    if (deferVisualUpdateToFrameBoundary) {
      final token = Object();
      _deferredReadVisualUpdates[entryId] = token;
      unawaited(
        SchedulerBinding.instance.endOfFrame.then((_) {
          if (!identical(_deferredReadVisualUpdates[entryId], token)) return;
          _deferredReadVisualUpdates.remove(entryId);
          updateVisualState();
        }),
      );
      return;
    }
    _deferredReadVisualUpdates.remove(entryId);
    updateVisualState();
  }

  void markAsUnreadLocal(String entryId) {
    if (entryId.trim().isEmpty) return;
    _probeLocallyReadIds.remove(entryId);
    _probeReportedReappearedIds.remove(entryId);
    _deferredReadVisualUpdates.remove(entryId);
    _cancelDeferredArticleStateNotification(entryId);
    GStorage.readStatus.delete(entryId);
    LocalArticleDbService.setReadState(entryId, false);
    _updateReadStateInMemory(entryId, false);
    ArticleStateNotifier.tick(entryId);
  }

  void setManyReadStatesLocal(
    Iterable<ArticleModel> source, {
    required bool isRead,
  }) {
    final byId = <String, ArticleModel>{
      for (final article in source)
        if (article.entryId.trim().isNotEmpty) article.entryId: article,
    };
    if (byId.isEmpty) return;

    for (final entry in byId.entries) {
      final entryId = entry.key;
      if (isRead) {
        GStorage.readStatus.put(entryId, true);
      } else {
        GStorage.readStatus.delete(entryId);
      }
      LocalArticleDbService.setReadState(
        entryId,
        isRead,
        recordHistory: isRead,
      );
      _deferredReadVisualUpdates.remove(entryId);
      _cancelDeferredArticleStateNotification(entryId);
    }

    allArticles.value = allArticles
        .map(
          (article) => byId.containsKey(article.entryId)
              ? _copyArticleWithReadState(article, isRead)
              : article,
        )
        .toList(growable: false);
    resetTimelineListAnimation(
      reason: isRead ? 'batch.markRead' : 'batch.markUnread',
    );
    _applyFilter();
    _updateFilterCount();
    ArticleStateNotifier.tickAll();
  }

  /// Broadcast the read-state change after the list removal has painted.
  ///
  /// Other pages subscribe to [ArticleStateNotifier] and may synchronously
  /// rebuild large local lists. Keeping that fan-out outside the removal
  /// window prevents it from consuming nearly every exit-animation frame.
  void completeDeferredReadTransition(String entryId) {
    final token = _deferredArticleStateNotifications[entryId];
    if (token == null) return;
    _deferredArticleStateNotificationFallbacks.remove(entryId)?.cancel();
    unawaited(
      SchedulerBinding.instance.endOfFrame.then((_) {
        if (!identical(_deferredArticleStateNotifications[entryId], token)) {
          return;
        }
        _deferredArticleStateNotifications.remove(entryId);
        ArticleStateNotifier.tick(entryId);
      }),
    );
  }

  void _deferArticleStateNotification(String entryId) {
    _cancelDeferredArticleStateNotification(entryId);
    final token = Object();
    _deferredArticleStateNotifications[entryId] = token;
    _deferredArticleStateNotificationFallbacks[entryId] = Timer(
      const Duration(seconds: 1),
      () {
        if (!identical(_deferredArticleStateNotifications[entryId], token)) {
          return;
        }
        _deferredArticleStateNotificationFallbacks.remove(entryId);
        _deferredArticleStateNotifications.remove(entryId);
        ArticleStateNotifier.tick(entryId);
      },
    );
  }

  void _cancelDeferredArticleStateNotification(String entryId) {
    _deferredArticleStateNotifications.remove(entryId);
    _deferredArticleStateNotificationFallbacks.remove(entryId)?.cancel();
  }

  @override
  void onClose() {
    _accountWorker?.dispose();
    for (final timer in _deferredArticleStateNotificationFallbacks.values) {
      timer.cancel();
    }
    _deferredArticleStateNotificationFallbacks.clear();
    _deferredArticleStateNotifications.clear();
    _deferredReadVisualUpdates.clear();
    super.onClose();
  }

  bool get hasMore => selectedMode.value != TimelineViewMode.read && _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  int get timelineListResetVersion => _timelineListResetVersion;
  String get timelineScopeKey => _timelineScopeKey;

  void setTimelineScope({
    bool silent = false,
    String? feedId,
    String? category,
  }) {
    assert(feedId == null || category == null);
    if (isSilentSelected.value == silent &&
        selectedFeedId.value == feedId &&
        selectedCategory.value == category) {
      return;
    }

    resetTimelineListAnimation(reason: 'scope.change');
    _isBatchingScopeChange = true;
    try {
      isSilentSelected.value = silent;
      selectedFeedId.value = feedId;
      selectedCategory.value = category;
    } finally {
      _isBatchingScopeChange = false;
    }
    _handleScopeChanged();
  }

  void resetTimelineListAnimation({required String reason}) {
    _timelineListResetVersion++;
    if (_animationProbeRequested && kDebugMode && Platform.isMacOS) {
      debugPrintSynchronously(
        '[TimelineListResetProbe] version=$_timelineListResetVersion '
        'reason=$reason count=${articles.length} '
        'mode=${selectedMode.value.name} scope=$_timelineScopeKey',
        wrapWidth: 2000,
      );
    }
  }

  void _handleScopeFieldChanged() {
    if (_isBatchingScopeChange) return;
    _handleScopeChanged();
  }

  void _handleScopeChanged() {
    _updateTimelineScopeKey();
    _applyFilter();
    selectedArticle.value = null;
  }

  void _updateTimelineScopeKey() {
    final silent = isSilentSelected.value ? 'silent' : 'normal';
    _timelineScopeKey =
        '$silent:${selectedCategory.value ?? ''}:${selectedFeedId.value ?? ''}';
  }

  int get unreadCount => allArticles
      .where((a) => !a.isRead && !FeedSilentSettingsService.isSilent(a.feedId))
      .length;
  int get readCount => allArticles
      .where((a) => a.isRead && !FeedSilentSettingsService.isSilent(a.feedId))
      .length;
  int get allCount => allArticles
      .where((a) => !FeedSilentSettingsService.isSilent(a.feedId))
      .length;

  int get silentUnreadCount => allArticles
      .where((a) => !a.isRead && FeedSilentSettingsService.isSilent(a.feedId))
      .length;
  int get silentReadCount => allArticles
      .where((a) => a.isRead && FeedSilentSettingsService.isSilent(a.feedId))
      .length;
  int get silentAllCount => allArticles
      .where((a) => FeedSilentSettingsService.isSilent(a.feedId))
      .length;

  void _updateAppBadge() {
    if (Platform.isMacOS) {
      final unread = unreadCount;
      if (unread == 0) {
        AppBadger.removeBadge();
      } else {
        AppBadger.updateBadgeCount(unread);
      }
      return;
    }

    final strategy = GStorage.setting.get(
      StorageKeys.badgeStrategy,
      defaultValue: 'unread_count',
    );
    if (strategy == 'off') {
      AppBadger.removeBadge();
      return;
    }

    final unread = unreadCount;
    if (unread == 0) {
      AppBadger.removeBadge();
    } else {
      if (strategy == 'dot_only') {
        AppBadger.updateBadgeCount(1);
      } else {
        AppBadger.updateBadgeCount(unread);
      }
    }
  }

  List<ArticleModel> get searchSourceArticles => allArticles;
  String get emptyMessage => switch (selectedMode.value) {
    TimelineViewMode.unread => '没有未读文章',
    TimelineViewMode.all => '本地文章库为空',
    TimelineViewMode.read => '暂无已读文章',
  };

  void bindScrollToTopHandler(Future<void> Function()? handler) {
    _scrollToTopHandler = handler;
  }

  Future<void> scrollToTop() async {
    await _scrollToTopHandler?.call();
  }

  void _loadFromLocalDatabase({required String resetReason}) {
    final local = LocalArticleDbService.readAllArticles();
    allArticles.value = _mergeLocalReadState(local);
    resetTimelineListAnimation(reason: resetReason);
    _applyFilter();
    _updateFilterCount();
    if (allArticles.isNotEmpty ||
        selectedMode.value != TimelineViewMode.unread) {
      loadingState.value = Success(articles.toList());
    }
  }

  void _applyFilter() {
    final mode = selectedMode.value;
    final feedId = selectedFeedId.value;
    final category = selectedCategory.value;
    final silentMode = isSilentSelected.value;

    final source = allArticles.where((a) {
      final isSilent = FeedSilentSettingsService.isSilent(a.feedId);

      if (silentMode) {
        if (!isSilent) return false;
      } else {
        if (feedId == null && isSilent) return false;
      }

      if (feedId != null && a.feedId != feedId) return false;
      if (category != null && a.displayCategory != category) return false;
      return true;
    });

    final filtered = switch (mode) {
      TimelineViewMode.unread => source.where((a) => !a.isRead).toList(),
      TimelineViewMode.read => source.where((a) => a.isRead).toList(),
      TimelineViewMode.all => source.toList(),
    };
    filtered.sort(_compareArticlesForCurrentSort);
    articles.value = filtered;
    if (_animationProbeRequested &&
        kDebugMode &&
        Platform.isMacOS &&
        mode == TimelineViewMode.unread) {
      for (final article in filtered) {
        if (!_probeLocallyReadIds.contains(article.entryId) || article.isRead) {
          continue;
        }
        if (_probeReportedReappearedIds.add(article.entryId)) {
          _logReadStateProbe(article.entryId, 'unread-list.reappeared');
        }
      }
    }
  }

  void _logReadStateProbe(String entryId, String event) {
    if (!_animationProbeRequested || !kDebugMode || !Platform.isMacOS) return;
    final shortId = entryId.length <= 8
        ? entryId
        : entryId.substring(entryId.length - 8);
    debugPrintSynchronously(
      '[TimelineReadStateProbe] id=$shortId event=$event '
      'pending=${ReadSyncService.pendingReadItems.any((item) => item.entryId == entryId)} '
      'override=${GStorage.readStatus.get(entryId)}',
      wrapWidth: 2000,
    );
  }

  int _compareArticlesForCurrentSort(ArticleModel a, ArticleModel b) {
    final mode = selectedSortMode.value;
    if (mode == TimelineSortMode.newest) {
      return _compareArticleByTimeDesc(a, b);
    }

    final lengthA = ArticleLengthEstimator.estimateReadingHeight(a);
    final lengthB = ArticleLengthEstimator.estimateReadingHeight(b);
    final lengthCompare = mode == TimelineSortMode.longest
        ? lengthB.compareTo(lengthA)
        : lengthA.compareTo(lengthB);
    if (lengthCompare != 0) return lengthCompare;
    return _compareArticleByTimeDesc(a, b);
  }

  int _compareArticleByTimeDesc(ArticleModel a, ArticleModel b) {
    final ta = _timeScore(a) ?? 0;
    final tb = _timeScore(b) ?? 0;
    return tb.compareTo(ta);
  }

  void _updateFilterCount() {
    int count = 0;
    for (final a in allArticles) {
      if (a.isRejectedByAi && !a.isRead) count++;
    }
    filterCount.value = count;
  }

  void _syncSingleArticleFromDb(String entryId) {
    final idx = allArticles.indexWhere((a) => a.entryId == entryId);
    if (idx < 0) return;

    final previousTimelineOrder = articles
        .map((article) => article.entryId)
        .toList(growable: false);

    final raw = GStorage.articleDb.get(entryId);
    if (raw is! Map) return;

    final updatedFromDb = ArticleModel.fromCache(
      Map<String, dynamic>.from(raw),
    );

    // 保护可能尚未同步到 DB 的本地“已读”状态
    final localOverride = GStorage.readStatus.get(entryId);
    final mergedRead = localOverride == true ? true : updatedFromDb.isRead;

    final finalUpdated = ArticleModel(
      entryId: updatedFromDb.entryId,
      feedId: updatedFromDb.feedId,
      feedTitle: updatedFromDb.feedTitle,
      feedImage: updatedFromDb.feedImage,
      title: updatedFromDb.title,
      url: updatedFromDb.url,
      content: updatedFromDb.content,
      publishedAt: updatedFromDb.publishedAt,
      isRead: mergedRead,
      category: updatedFromDb.category,
      subscriptionCategory: updatedFromDb.subscriptionCategory,
      author: updatedFromDb.author,
      imageUrl: updatedFromDb.imageUrl,
      isRejectedByAi: updatedFromDb.isRejectedByAi,
      filterReason: updatedFromDb.filterReason,
      filterReviewed: updatedFromDb.filterReviewed,
      filteredAt: updatedFromDb.filteredAt,
      userAction: updatedFromDb.userAction,
    );

    allArticles[idx] = finalUpdated;
    _applyFilter();
    final currentTimelineOrder = articles
        .map((article) => article.entryId)
        .toList(growable: false);
    if (!listEquals(previousTimelineOrder, currentTimelineOrder)) {
      resetTimelineListAnimation(reason: 'article.structureChange');
    }
    _updateFilterCount();
  }

  void _updateReadStateInMemory(
    String entryId,
    bool isRead, {
    bool updateSelectedArticle = true,
    bool useIncrementalUnreadRemoval = false,
  }) {
    final idx = allArticles.indexWhere((a) => a.entryId == entryId);
    if (idx < 0) return;

    final a = allArticles[idx];
    if (a.isRead == isRead) return;

    final updated = _copyArticleWithReadState(a, isRead);
    if (useIncrementalUnreadRemoval &&
        isRead &&
        selectedMode.value == TimelineViewMode.unread) {
      // A normal allArticles write would synchronously recalculate the app
      // badge, while _applyFilter would rescan and sort the entire article
      // database. The persisted state is already current; the deferred global
      // notification updates the full in-memory model after the card leaves.
      final visibleIndex = articles.indexWhere(
        (article) => article.entryId == entryId,
      );
      if (visibleIndex >= 0) {
        articles.removeAt(visibleIndex);
      }
      return;
    }

    allArticles[idx] = updated;
    _applyFilter();
    _updateFilterCount();

    // Update selectedArticle if it was modified
    if (updateSelectedArticle && selectedArticle.value?.entryId == entryId) {
      selectedArticle.value = updated;
    }
  }

  ArticleModel _copyArticleWithReadState(ArticleModel article, bool isRead) {
    return ArticleModel(
      entryId: article.entryId,
      feedId: article.feedId,
      feedTitle: article.feedTitle,
      feedImage: article.feedImage,
      title: article.title,
      url: article.url,
      content: article.content,
      publishedAt: article.publishedAt,
      isRead: isRead,
      category: article.category,
      subscriptionCategory: article.subscriptionCategory,
      author: article.author,
      imageUrl: article.imageUrl,
      isRejectedByAi: article.isRejectedByAi,
      filterReason: article.filterReason,
      filterReviewed: article.filterReviewed,
      filteredAt: article.filteredAt,
      userAction: article.userAction,
    );
  }

  List<ArticleModel> _mergeLocalReadState(List<ArticleModel> source) {
    return source.map((a) {
      final readVal = LocalArticleDbService.readOverrideOf(a.entryId);
      if (readVal != null && readVal != a.isRead) {
        return ArticleModel(
          entryId: a.entryId,
          feedId: a.feedId,
          feedTitle: a.feedTitle,
          feedImage: a.feedImage,
          title: a.title,
          url: a.url,
          content: a.content,
          publishedAt: a.publishedAt,
          isRead: readVal,
          category: a.category,
          subscriptionCategory: a.subscriptionCategory,
          author: a.author,
          imageUrl: a.imageUrl,
          isRejectedByAi: a.isRejectedByAi,
          filterReason: a.filterReason,
          filterReviewed: a.filterReviewed,
          filteredAt: a.filteredAt,
          userAction: a.userAction,
        );
      }
      return a;
    }).toList();
  }
}
