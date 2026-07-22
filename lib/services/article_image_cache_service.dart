import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../models/article.dart';
import '../utils/article_content_utils.dart';
import '../utils/storage.dart';
import 'article_image_service.dart';

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

  static const String _cacheKeyPrefix = 'article_body_v1';
  static const String _registryPrefix = 'articleImageKeys:';

  static final List<_ImageDownloadTask> _foregroundQueue = [];
  static final List<_ImageDownloadTask> _backgroundQueue = [];
  static final Set<String> _queuedKeys = {};
  static final Set<String> _runningKeys = {};
  static final Map<String, Set<String>> _registeredKeys = {};
  static final Map<String, DateTime> _cleanupDueAt = {};
  static final Set<String> _activeArticleIds = {};

  static Timer? _cleanupTimer;
  static int _runningDownloads = 0;
  static int _prefetchGeneration = 0;
  static bool _cleanupRunning = false;

  static BaseCacheManager get _cacheManager => DefaultCacheManager();

  static bool get _enabled => Platform.isMacOS || Platform.isAndroid;

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
      if (foreground) {
        final backgroundIndex = _backgroundQueue.indexWhere(
          (queued) => cacheKey(queued.articleId, queued.imageUrl) == key,
        );
        if (backgroundIndex >= 0) {
          final promoted = _backgroundQueue.removeAt(backgroundIndex);
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
    try {
      final cached = await _cacheManager.getFileFromCache(key);
      if (cached == null) {
        await _cacheManager.getSingleFile(
          task.imageUrl,
          key: key,
          headers: ArticleImageService.httpHeaders,
        );
      }
    } catch (_) {
      // Prefetching is opportunistic; normal article rendering owns retries.
    } finally {
      _runningKeys.remove(key);
      _runningDownloads--;
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

        final keys = _keysFor(articleId).toList(growable: false);
        for (final key in keys) {
          await _cacheManager.removeFile(key);
          await Future<void>.delayed(Duration.zero);
        }
        _registeredKeys.remove(articleId);
        await GStorage.localCache.delete('$_registryPrefix$articleId');
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

  const _ImageDownloadTask({
    required this.articleId,
    required this.imageUrl,
    required this.generation,
  });
}
