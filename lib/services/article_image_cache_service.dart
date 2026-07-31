import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../models/article.dart';
import '../utils/article_content_utils.dart';
import '../utils/storage.dart';
import 'article_image_retry_scheduler.dart';
import 'article_image_service.dart';

@immutable
class ArticleImageRetryState {
  const ArticleImageRetryState({
    required this.retrying,
    required this.successRevision,
  });

  final bool retrying;
  final int successRevision;

  @override
  bool operator ==(Object other) =>
      other is ArticleImageRetryState &&
      retrying == other.retrying &&
      successRevision == other.successRevision;

  @override
  int get hashCode => Object.hash(retrying, successRevision);
}

/// Article-body image prefetching and article-scoped cache cleanup.
abstract final class ArticleImageCacheService {
  static const int macosMaxConcurrentDownloads = 16;
  static const int macosForegroundImageLimit = 4;
  static const int macosImagesPerArticle = 8;
  static const int androidMaxConcurrentDownloads = 4;
  static const int androidForegroundImageLimit = 2;
  static const int androidImagesPerArticle = 4;
  static const int androidBackgroundArticleLimit = 50;
  static const Duration readCacheRetention = Duration(minutes: 5);

  /// 失败图片自动重试次数上限。达到上限后停止自动重试，失败记录保留，
  /// 等待全局刷新时由 [retryFailedPrefetches] 重新排查，或用户手动点击重试。
  static const int maxAutoRetries = 3;

  /// 指数退避间隔：第 1/2/3 次自动重试前分别等待 1s/2s/4s。
  /// 用一次性 [Timer] 调度，无后台轮询。
  static const List<Duration> _autoRetryBackoff = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  static const String _cacheKeyPrefix = 'article_body_v1';
  static const String _registryPrefix = 'articleImageKeys:';
  static const String _failedRegistryPrefix = 'articleImageFailedKeys:';

  static final List<_ImageDownloadTask> _foregroundQueue = [];
  static final List<_ImageDownloadTask> _backgroundQueue = [];
  static final Set<String> _queuedKeys = {};
  static final Set<String> _runningKeys = {};
  static final Map<String, Set<String>> _registeredKeys = {};
  static final Map<String, DateTime> _cleanupDueAt = {};
  static final Set<String> _activeArticleIds = {};

  /// 失败图片登记：articleId → 失败的 imageUrl 集合（已规范化、含代理）。
  /// 落盘到 [GStorage.localCache]，进程重启后 [retryFailedPrefetches] 仍可重扫。
  static final Map<String, Set<String>> _failedImageUrls = {};

  static final ArticleImageRetryScheduler _retryScheduler =
      ArticleImageRetryScheduler(backoff: _autoRetryBackoff);
  static final Map<String, ValueNotifier<ArticleImageRetryState>>
  _retryStateNotifiers = {};
  static final Map<String, int> _retryStateUsers = {};
  static final Map<String, int> _successfulRetryRevisions = {};

  static Timer? _cleanupTimer;
  static int _runningDownloads = 0;
  static int _prefetchGeneration = 0;
  static bool _cleanupRunning = false;

  static BaseCacheManager get _cacheManager => DefaultCacheManager();

  static bool get _enabled => Platform.isMacOS || Platform.isAndroid;

  static ValueListenable<ArticleImageRetryState> acquireRetryState(
    String articleId,
    String imageUrl,
  ) {
    final key = cacheKey(articleId, imageUrl);
    _retryStateUsers[key] = (_retryStateUsers[key] ?? 0) + 1;
    return _retryStateNotifiers.putIfAbsent(
      key,
      () => ValueNotifier(_retrySnapshot(key)),
    );
  }

  static void releaseRetryState(String articleId, String imageUrl) {
    final key = cacheKey(articleId, imageUrl);
    final users = (_retryStateUsers[key] ?? 0) - 1;
    if (users > 0) {
      _retryStateUsers[key] = users;
      return;
    }
    _retryStateUsers.remove(key);
    _retryStateNotifiers.remove(key)?.dispose();
    _successfulRetryRevisions.remove(key);
  }

  static ArticleImageRetryState _retrySnapshot(String key) {
    return ArticleImageRetryState(
      retrying:
          _retryScheduler.isWaiting(key) ||
          _queuedKeys.contains(key) ||
          _runningKeys.contains(key),
      successRevision: _successfulRetryRevisions[key] ?? 0,
    );
  }

  static void _publishRetryState(String key) {
    final notifier = _retryStateNotifiers[key];
    if (notifier == null) return;
    final next = _retrySnapshot(key);
    if (notifier.value != next) notifier.value = next;
  }

  static _ImageCacheProfile get _profile => Platform.isAndroid
      ? const _ImageCacheProfile(
          maxConcurrentDownloads: androidMaxConcurrentDownloads,
          foregroundImageLimit: androidForegroundImageLimit,
          imagesPerArticle: androidImagesPerArticle,
          backgroundArticleLimit: androidBackgroundArticleLimit,
        )
      : const _ImageCacheProfile(
          maxConcurrentDownloads: macosMaxConcurrentDownloads,
          foregroundImageLimit: macosForegroundImageLimit,
          imagesPerArticle: macosImagesPerArticle,
        );

  static String cacheKey(String articleId, String imageUrl) {
    return '$_cacheKeyPrefix:$articleId:$imageUrl';
  }

  static String displayCacheKey(String articleId, String imageUrl) {
    return _enabled ? cacheKey(articleId, imageUrl) : 'v2_$imageUrl';
  }

  static String resizedCacheKey(String baseKey, {int? width, int? height}) {
    var key = 'resized';
    if (width != null) key += '_w$width';
    if (height != null) key += '_h$height';
    return '${key}_$baseKey';
  }

  static bool isBackgroundPrefetchable(String imageUrl) {
    final uri = Uri.tryParse(imageUrl);
    final lowerPath = (uri?.path ?? imageUrl).toLowerCase();
    final lowerQuery = (uri?.query ?? '').toLowerCase();
    return !lowerPath.endsWith('.gif') &&
        !lowerPath.endsWith('.apng') &&
        !lowerQuery.contains('format=gif') &&
        !lowerQuery.contains('format=apng');
  }

  static Future<File> getImageFile(String articleId, String imageUrl) {
    registerImage(articleId, imageUrl);
    return _cacheManager.getSingleFile(
      imageUrl,
      key: cacheKey(articleId, imageUrl),
      headers: ArticleImageService.httpHeaders,
    );
  }

  /// Registers the keys created by CachedNetworkImage so article cleanup can
  /// remove both the original object and any disk-resized variant.
  static void registerImage(
    String articleId,
    String imageUrl, {
    int? maxWidth,
    int? maxHeight,
  }) {
    if (!_enabled || articleId.isEmpty || imageUrl.isEmpty) return;

    final baseKey = cacheKey(articleId, imageUrl);
    final keys = _keysFor(articleId);
    var changed = keys.add(baseKey);
    if (maxWidth != null || maxHeight != null) {
      changed =
          keys.add(
            resizedCacheKey(baseKey, width: maxWidth, height: maxHeight),
          ) ||
          changed;
    }
    if (changed) {
      unawaited(
        GStorage.localCache.put(
          '$_registryPrefix$articleId',
          keys.toList(growable: false),
        ),
      );
    }
  }

  static void markArticleActive(String articleId) {
    if (!_enabled || articleId.isEmpty) return;
    _activeArticleIds.add(articleId);
  }

  static void markArticleInactive(String articleId) {
    if (!_enabled || articleId.isEmpty) return;
    _activeArticleIds.remove(articleId);
    final rawTimestamp = GStorage.readHistory.get(articleId);
    if (rawTimestamp is int) {
      final dueAt = DateTime.fromMillisecondsSinceEpoch(
        rawTimestamp,
      ).add(readCacheRetention);
      _cleanupDueAt[articleId] = dueAt;
    }
    final dueAt = _cleanupDueAt[articleId];
    if (dueAt != null && !dueAt.isAfter(DateTime.now())) {
      unawaited(_runCleanup());
    }
  }

  /// Called whenever readHistory changes. One timer services all articles.
  static void onReadHistoryChanged(String articleId, {required bool isRead}) {
    if (!_enabled || articleId.isEmpty) return;

    if (!isRead) {
      _cleanupDueAt.remove(articleId);
      _removeQueuedTasksForArticle(articleId);
      _scheduleNextCleanup();
      return;
    }

    _removeQueuedTasksForArticle(articleId);
    final rawTimestamp = GStorage.readHistory.get(articleId);
    if (rawTimestamp is int) {
      _cleanupDueAt[articleId] = DateTime.fromMillisecondsSinceEpoch(
        rawTimestamp,
      ).add(readCacheRetention);
      _scheduleNextCleanup();
    }
  }

  /// Promotes the first images of the open article ahead of background work.
  static void prioritizeArticle(String articleId, List<String> imageUrls) {
    if (!_enabled || articleId.isEmpty) return;
    markArticleActive(articleId);

    final tasks = imageUrls
        .take(_profile.foregroundImageLimit)
        .map(
          (url) => _ImageDownloadTask(
            articleId: articleId,
            imageUrl: url,
            generation: _prefetchGeneration,
          ),
        )
        .toList(growable: false);
    for (final task in tasks.reversed) {
      _enqueue(task, foreground: true, atFront: true);
    }
    _pumpQueue();
  }

  static Future<void> prefetchUnreadArticle(ArticleModel article) async {
    if (!_enabled || article.isRead || article.entryId.isEmpty) return;
    final content = article.content ?? '';
    if (content.trim().isEmpty) return;

    final generation = _prefetchGeneration;
    final plan = await Isolate.run(
      () => buildPrefetchPlan([
        {
          'articleId': article.entryId,
          'content': content,
          'sourceUrl': article.url,
        },
      ], maxImages: _profile.imagesPerArticle),
    );
    for (final item in plan) {
      _enqueue(
        _ImageDownloadTask(
          articleId: item['articleId']!,
          imageUrl: item['imageUrl']!,
          generation: generation,
        ),
        foreground: false,
      );
    }
    _pumpQueue();
  }

  /// Rebuilds the background queue from all locally known unread articles.
  /// The plan is parsed off the UI isolate and ordered article-by-article.
  static Future<void> refresh(List<ArticleModel> articles) async {
    if (!_enabled) return;

    final generation = ++_prefetchGeneration;
    _clearBackgroundQueue();
    await _reconcileCleanupSchedule(articles);

    final candidates = articles
        .where((article) => !article.isRead)
        .where((article) => (article.content ?? '').trim().isNotEmpty)
        .map(
          (article) => <String, String>{
            'articleId': article.entryId,
            'content': article.content!,
            'sourceUrl': article.url,
          },
        );
    final articleLimit = _profile.backgroundArticleLimit;
    final source =
        (articleLimit == null ? candidates : candidates.take(articleLimit))
            .toList(growable: false);
    if (source.isEmpty) return;

    final plan = await Isolate.run(
      () => buildPrefetchPlan(source, maxImages: _profile.imagesPerArticle),
    );
    if (generation != _prefetchGeneration) return;

    for (final item in plan) {
      final articleId = item['articleId']!;
      final imageUrl = item['imageUrl']!;
      _enqueue(
        _ImageDownloadTask(
          articleId: articleId,
          imageUrl: imageUrl,
          generation: generation,
        ),
        foreground: false,
      );
    }
    _pumpQueue();
  }

  static List<Map<String, String>> buildPrefetchPlan(
    List<Map<String, String>> articles, {
    int maxImages = macosImagesPerArticle,
    int? maxArticles,
  }) {
    final plan = <Map<String, String>>[];
    final source = maxArticles == null ? articles : articles.take(maxArticles);
    for (final article in source) {
      final articleId = article['articleId'] ?? '';
      final content = article['content'] ?? '';
      final sourceUrl = article['sourceUrl'];
      if (articleId.isEmpty || content.trim().isEmpty) continue;

      final normalized = ArticleContentUtils.normalizeHtml(
        content,
        sourceUrl: sourceUrl,
      );
      final urls = ArticleContentUtils.extractImageUrls(
        normalized,
      ).where(isBackgroundPrefetchable).take(maxImages);
      for (final imageUrl in urls) {
        plan.add({'articleId': articleId, 'imageUrl': imageUrl});
      }
    }
    return plan;
  }

  static void _enqueue(
    _ImageDownloadTask task, {
    required bool foreground,
    bool atFront = false,
  }) {
    if (task.articleId.isEmpty || task.imageUrl.isEmpty) return;
    final key = cacheKey(task.articleId, task.imageUrl);
    if (_runningKeys.contains(key)) return;
    if (_queuedKeys.contains(key)) {
      final foregroundIndex = _foregroundQueue.indexWhere(
        (queued) => cacheKey(queued.articleId, queued.imageUrl) == key,
      );
      final backgroundIndex = _backgroundQueue.indexWhere(
        (queued) => cacheKey(queued.articleId, queued.imageUrl) == key,
      );
      if (task.forceNetwork) {
        if (foregroundIndex >= 0) {
          _foregroundQueue[foregroundIndex] = task;
        } else if (backgroundIndex >= 0) {
          _backgroundQueue[backgroundIndex] = task;
        }
      }
      if (foreground) {
        if (backgroundIndex >= 0) {
          final promoted = task.forceNetwork
              ? task
              : _backgroundQueue[backgroundIndex];
          _backgroundQueue.removeAt(backgroundIndex);
          if (atFront) {
            _foregroundQueue.insert(0, promoted);
          } else {
            _foregroundQueue.add(promoted);
          }
        }
      }
      return;
    }

    registerImage(task.articleId, task.imageUrl);
    _queuedKeys.add(key);
    final queue = foreground ? _foregroundQueue : _backgroundQueue;
    if (atFront) {
      queue.insert(0, task);
    } else {
      queue.add(task);
    }
  }

  static void _pumpQueue() {
    if (!_enabled) return;
    while (_runningDownloads < _profile.maxConcurrentDownloads) {
      final task = _nextTask();
      if (task == null) return;

      final key = cacheKey(task.articleId, task.imageUrl);
      _queuedKeys.remove(key);
      _runningKeys.add(key);
      _runningDownloads++;
      unawaited(_download(task, key));
    }
  }

  static _ImageDownloadTask? _nextTask() {
    if (_foregroundQueue.isNotEmpty) {
      return _foregroundQueue.removeAt(0);
    }
    while (_backgroundQueue.isNotEmpty) {
      final task = _backgroundQueue.removeAt(0);
      if (task.generation == _prefetchGeneration) return task;
      _queuedKeys.remove(cacheKey(task.articleId, task.imageUrl));
    }
    return null;
  }

  static Future<void> _download(_ImageDownloadTask task, String key) async {
    var failed = false;
    try {
      if (task.forceNetwork) {
        await _cacheManager.removeFile(key);
        await _cacheManager.getSingleFile(
          task.imageUrl,
          key: key,
          headers: ArticleImageService.httpHeaders,
        );
      } else {
        final cached = await _cacheManager.getFileFromCache(key);
        if (cached == null) {
          await _cacheManager.getSingleFile(
            task.imageUrl,
            key: key,
            headers: ArticleImageService.httpHeaders,
          );
        }
      }
      recordSuccess(task.articleId, task.imageUrl);
    } catch (_) {
      failed = true;
      recordFailure(task.articleId, task.imageUrl);
    } finally {
      _runningKeys.remove(key);
      _runningDownloads--;
      // Only schedule after the running key is released. Scheduling inside the
      // catch block is rejected by the duplicate-work guard.
      if (failed) _scheduleAutoRetry(task);
      _publishRetryState(key);
      _pumpQueue();
      final dueAt = _cleanupDueAt[task.articleId];
      if (dueAt != null && !dueAt.isAfter(DateTime.now())) {
        unawaited(_runCleanup());
      }
    }
  }

  static Set<String> _keysFor(String articleId) {
    final cached = _registeredKeys[articleId];
    if (cached != null) return cached;

    final raw = GStorage.localCache.get('$_registryPrefix$articleId');
    final keys = raw is List ? raw.whereType<String>().toSet() : <String>{};
    _registeredKeys[articleId] = keys;
    return keys;
  }

  // ── 失败图片状态 ────────────────────────────────────────────────────
  //
  // 重试职责统一收敛到本 service：正文渲染和后台预取两条路径的失败都经
  // [recordFailure] 登记，由 [_scheduleAutoRetry] 在后台带指数退避重试，
  // 成功后经 [recordSuccess] 清除失败标记并通知正文刷新。失败记录落盘，
  // 进程重启后仍可由 [retryFailedPrefetches] 在全局刷新时重新排查。

  static Set<String> _failedUrlsFor(String articleId) {
    final cached = _failedImageUrls[articleId];
    if (cached != null) return cached;

    final raw = GStorage.localCache.get('$_failedRegistryPrefix$articleId');
    final urls = raw is List ? raw.whereType<String>().toSet() : <String>{};
    _failedImageUrls[articleId] = urls;
    return urls;
  }

  static void _persistFailedUrls(String articleId) {
    final urls = _failedImageUrls[articleId];
    if (urls == null || urls.isEmpty) {
      unawaited(GStorage.localCache.delete('$_failedRegistryPrefix$articleId'));
      return;
    }
    unawaited(
      GStorage.localCache.put(
        '$_failedRegistryPrefix$articleId',
        urls.toList(growable: false),
      ),
    );
  }

  /// 登记一次图片加载失败。供正文渲染层与 [_download] 共用。同一 url 重复
  /// 登记幂等，只在状态变化时落盘。是否安排退避重试由调用方按需触发
  /// （前台 errorWidget 经 [scheduleRetryFromUi]，后台 _download 直接调
  /// [_scheduleAutoRetry]）。
  static void recordFailure(String articleId, String imageUrl) {
    if (!_enabled || articleId.isEmpty || imageUrl.isEmpty) return;
    final urls = _failedUrlsFor(articleId);
    if (urls.add(imageUrl)) {
      _persistFailedUrls(articleId);
    }
  }

  /// Clears failure state and advances the image-specific success revision so
  /// only the affected foreground image is recreated from the populated cache.
  static void recordSuccess(String articleId, String imageUrl) {
    if (!_enabled || articleId.isEmpty || imageUrl.isEmpty) return;
    final key = cacheKey(articleId, imageUrl);
    final urls = _failedImageUrls[articleId];
    if (urls == null || urls.isEmpty) return;
    if (urls.remove(imageUrl)) {
      _retryScheduler.reset(key);
      if (_retryStateNotifiers.containsKey(key)) {
        _successfulRetryRevisions[key] =
            (_successfulRetryRevisions[key] ?? 0) + 1;
      }
      if (urls.isEmpty) {
        _failedImageUrls.remove(articleId);
      }
      _persistFailedUrls(articleId);
      _publishRetryState(key);
    }
  }

  /// 安排一次带指数退避的自动重试。达到 [maxAutoRetries] 后停止，失败
  /// 记录保留，等待全局刷新或手动重试。用一次性 [Timer]，无后台轮询。
  /// Existing timers and queue/running state make repeated calls idempotent.
  /// Exhaustion publishes a final non-retrying state without restarting.
  static void _scheduleAutoRetry(_ImageDownloadTask task) {
    final key = cacheKey(task.articleId, task.imageUrl);
    if (_runningKeys.contains(key) || _queuedKeys.contains(key)) {
      return;
    }
    final result = _retryScheduler.schedule(
      key,
      onReady: () {
        if (!_failedUrlsFor(task.articleId).contains(task.imageUrl)) return;
        final foreground = _activeArticleIds.contains(task.articleId);
        _enqueue(
          _ImageDownloadTask(
            articleId: task.articleId,
            imageUrl: task.imageUrl,
            generation: _prefetchGeneration,
            forceNetwork: true,
          ),
          foreground: foreground,
          atFront: foreground,
        );
        _pumpQueue();
        _publishRetryState(key);
      },
      onExhausted: () => _publishRetryState(key),
    );
    if (result == RetryScheduleResult.scheduled) {
      _publishRetryState(key);
    }
  }

  /// Called after the foreground error widget has committed its frame.
  static void scheduleRetryFromUi(String articleId, String imageUrl) {
    if (!_enabled || articleId.isEmpty || imageUrl.isEmpty) return;
    recordFailure(articleId, imageUrl);
    _scheduleAutoRetry(
      _ImageDownloadTask(
        articleId: articleId,
        imageUrl: imageUrl,
        generation: _prefetchGeneration,
      ),
    );
  }

  /// 取消某篇自动重试中（等待退避 Timer）的任务，用于清理时停止退避。
  static void _cancelAutoRetryForArticle(String articleId) {
    final prefix = '$_cacheKeyPrefix:$articleId:';
    _retryScheduler.cancelWhere((key) => key.startsWith(prefix));
  }

  /// 供正文渲染层手动重试兜底调用：重置该图自动重试计数并立即重新入队。
  static void retryManually(String articleId, String imageUrl) {
    if (!_enabled || articleId.isEmpty || imageUrl.isEmpty) return;
    final key = cacheKey(articleId, imageUrl);
    recordFailure(articleId, imageUrl);
    _retryScheduler.reset(key);
    final foreground = _activeArticleIds.contains(articleId);
    _enqueue(
      _ImageDownloadTask(
        articleId: articleId,
        imageUrl: imageUrl,
        generation: _prefetchGeneration,
        forceNetwork: true,
      ),
      foreground: foreground,
      atFront: foreground,
    );
    _pumpQueue();
    _publishRetryState(key);
  }

  /// 全局刷新时重新排查所有失败图片，重新发起一轮（自动重试计数清零）。
  /// 由 [TimelineController] 在 [refresh] 之后调用。
  static Future<void> retryFailedPrefetches() async {
    if (!_enabled) return;

    // 收集当前内存 + 落盘的所有失败记录（重启后内存为空，需扫描落盘）。
    final articleIds = <String>{
      ..._failedImageUrls.keys,
      ...GStorage.localCache.keys
          .whereType<String>()
          .where((key) => key.startsWith(_failedRegistryPrefix))
          .map((key) => key.substring(_failedRegistryPrefix.length)),
    };

    for (final articleId in articleIds) {
      final urls = _failedUrlsFor(articleId).toList(growable: false);
      for (final imageUrl in urls) {
        final key = cacheKey(articleId, imageUrl);
        _retryScheduler.reset(key);
        _enqueue(
          _ImageDownloadTask(
            articleId: articleId,
            imageUrl: imageUrl,
            generation: _prefetchGeneration,
            forceNetwork: true,
          ),
          foreground: _activeArticleIds.contains(articleId),
        );
        _publishRetryState(key);
      }
    }
    _pumpQueue();
  }

  static Future<void> _reconcileCleanupSchedule(
    List<ArticleModel> articles,
  ) async {
    final readIds = articles
        .where((article) => article.isRead)
        .map((article) => article.entryId)
        .toSet();

    _cleanupDueAt.removeWhere((articleId, _) => !readIds.contains(articleId));
    for (final articleId in readIds) {
      final rawTimestamp = GStorage.readHistory.get(articleId);
      if (rawTimestamp is! int) continue;
      _cleanupDueAt[articleId] = DateTime.fromMillisecondsSinceEpoch(
        rawTimestamp,
      ).add(readCacheRetention);
    }
    await _runCleanup();
    _scheduleNextCleanup();
  }

  static void _scheduleNextCleanup() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    if (_cleanupDueAt.isEmpty) return;

    final now = DateTime.now();
    DateTime? next;
    for (final dueAt in _cleanupDueAt.values) {
      if (next == null || dueAt.isBefore(next)) next = dueAt;
    }
    final delay = next!.isAfter(now) ? next.difference(now) : Duration.zero;
    _cleanupTimer = Timer(delay, () => unawaited(_runCleanup()));
  }

  static Future<void> _runCleanup() async {
    if (_cleanupRunning || !_enabled) return;
    _cleanupRunning = true;
    try {
      final now = DateTime.now();
      final dueArticleIds = _cleanupDueAt.entries
          .where((entry) => !entry.value.isAfter(now))
          .map((entry) => entry.key)
          .toList(growable: false);

      for (final articleId in dueArticleIds) {
        if (_activeArticleIds.contains(articleId) ||
            _hasRunningTasksForArticle(articleId)) {
          _cleanupDueAt[articleId] = now.add(const Duration(minutes: 1));
          continue;
        }

        final rawArticle = GStorage.articleDb.get(articleId);
        final isStillRead = rawArticle is Map && rawArticle['isRead'] == true;
        final readTimestamp = GStorage.readHistory.get(articleId);
        if (!isStillRead || readTimestamp is! int) {
          _cleanupDueAt.remove(articleId);
          continue;
        }

        final dueAt = DateTime.fromMillisecondsSinceEpoch(
          readTimestamp,
        ).add(readCacheRetention);
        if (dueAt.isAfter(now)) {
          _cleanupDueAt[articleId] = dueAt;
          continue;
        }

        // Stop queued and delayed work synchronously before the first cache
        // deletion await. A timer cannot enqueue the same image mid-cleanup.
        _removeQueuedTasksForArticle(articleId);
        _cancelAutoRetryForArticle(articleId);

        final keys = _keysFor(articleId).toList(growable: false);
        for (final key in keys) {
          await _cacheManager.removeFile(key);
          await Future<void>.delayed(Duration.zero);
        }
        _registeredKeys.remove(articleId);
        await GStorage.localCache.delete('$_registryPrefix$articleId');
        _failedImageUrls.remove(articleId);
        await GStorage.localCache.delete('$_failedRegistryPrefix$articleId');
        _cleanupDueAt.remove(articleId);
      }
    } finally {
      _cleanupRunning = false;
      _scheduleNextCleanup();
    }
  }

  static void _clearBackgroundQueue() {
    for (final task in _backgroundQueue) {
      _queuedKeys.remove(cacheKey(task.articleId, task.imageUrl));
    }
    _backgroundQueue.clear();
  }

  static void _removeQueuedTasksForArticle(String articleId) {
    void removeFrom(List<_ImageDownloadTask> queue) {
      final removed = queue
          .where((task) => task.articleId == articleId)
          .toList(growable: false);
      queue.removeWhere((task) => task.articleId == articleId);
      for (final task in removed) {
        _queuedKeys.remove(cacheKey(task.articleId, task.imageUrl));
      }
    }

    removeFrom(_foregroundQueue);
    removeFrom(_backgroundQueue);
  }

  static bool _hasRunningTasksForArticle(String articleId) {
    final prefix = '$_cacheKeyPrefix:$articleId:';
    return _runningKeys.any((key) => key.startsWith(prefix));
  }
}

class _ImageCacheProfile {
  final int maxConcurrentDownloads;
  final int foregroundImageLimit;
  final int imagesPerArticle;
  final int? backgroundArticleLimit;

  const _ImageCacheProfile({
    required this.maxConcurrentDownloads,
    required this.foregroundImageLimit,
    required this.imagesPerArticle,
    this.backgroundArticleLimit,
  });
}

class _ImageDownloadTask {
  final String articleId;
  final String imageUrl;
  final int generation;
  final bool forceNetwork;

  const _ImageDownloadTask({
    required this.articleId,
    required this.imageUrl,
    required this.generation,
    this.forceNetwork = false,
  });
}
