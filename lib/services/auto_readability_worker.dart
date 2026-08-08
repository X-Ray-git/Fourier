import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;

import '../http/feed_http.dart';
import '../http/init.dart';

import '../models/article.dart';
import '../utils/article_content_utils.dart';
import '../utils/storage.dart';
import 'local_article_db_service.dart';
import 'feed_readability_settings_service.dart';
import 'auto_ai_queue_coordinator.dart';
import 'auto_filter_worker.dart';
import 'account_session_guard.dart';

/// 全文抓取队列 — 并发 3 的滚动补位调度
///
/// 全文抓取成功标记只在成功解析并持久化有效正文后写入；失败进入
/// 有限次数 + 指数退避的自动重试，并保留可诊断的失败状态。
/// 已开始抓取的文章即使完成前被标为已读，仍允许已开始的流水线继续
/// 进入翻译和摘要；尚未开始的等待任务在出队时若已标为已读则移除。
abstract final class AutoReadabilityWorker {
  static final _queue = <ArticleModel>[];
  static final _queuedIds = <String>{};
  static final _running = <String>{};

  /// 最大并发请求数
  static const int _concurrency = 3;

  /// 全文抓取失败后的自动重试次数上限（初始尝试之外的额外次数）。
  static const int _maxFetchRetryAttempts = 2;

  /// 指数退避：第 1/2 次自动重试前分别等待 2s / 5s。
  static const List<Duration> _fetchRetryBackoffs = [
    Duration(seconds: 2),
    Duration(seconds: 5),
  ];

  static final Map<String, Timer> _fetchRetryTimers = {};

  /// 失败状态诊断 key 前缀（值：{attempts, lastError, lastAt}）
  static const String _fetchStateKeyPrefix = 'readability_fetch_state_';

  /// 测试注入点：替换真实全文抓取调用。返回抓取到的原始 HTML；
  /// 返回 null 表示抓取失败。
  @visibleForTesting
  static Future<String?> Function(ArticleModel article)? debugFetchOverride;

  /// 入队一篇文章
  static void enqueueOne(ArticleModel article) {
    if (article.isRead) return;
    if (article.entryId.isEmpty) return;
    if (_running.contains(article.entryId)) return;
    if (!_queuedIds.add(article.entryId)) return;
    _queue.add(article);
    _pump();
  }

  /// 批量入队
  static void enqueueMany(List<ArticleModel> articles) {
    var added = false;
    for (final article in articles) {
      if (article.isRead || article.entryId.isEmpty) continue;
      if (_running.contains(article.entryId)) continue;
      if (!_queuedIds.add(article.entryId)) continue;
      _queue.add(article);
      added = true;
    }
    if (!added) return;
    _pump();
  }

  /// 滚动补位：运行中数量小于并发上限且队列非空时立即启动新任务。
  /// 等待期间被标为已读的任务在出队时移除，不再启动。
  static void _pump() {
    while (_running.length < _concurrency && _queue.isNotEmpty) {
      final article = _queue.removeAt(0);
      if (_isMarkedRead(article.entryId, article.isRead)) {
        _queuedIds.remove(article.entryId);
        continue;
      }
      _start(article);
    }
  }

  static bool _isMarkedRead(String entryId, bool fallback) {
    final raw = GStorage.articleDb.get(entryId);
    if (raw is Map) return raw['isRead'] == true;
    return fallback;
  }

  static void _start(ArticleModel article) {
    final accountRevision = AccountSessionGuard.revision;
    _running.add(article.entryId);
    unawaited(
      _processArticle(article).whenComplete(() {
        _running.remove(article.entryId);
        if (AccountSessionGuard.isCurrent(accountRevision)) {
          _queuedIds.remove(article.entryId);
        }
        _pump();
      }),
    );
  }

  static Future<void> _processArticle(ArticleModel article) async {
    final accountRevision = AccountSessionGuard.revision;
    ArticleModel processedArticle = article;
    var rawContent = article.content ?? '';

    if (article.category == 'inbox' && rawContent.isEmpty) {
      final inboxFetchedKey = 'inbox_detail_fetched_${article.entryId}';
      final hasInboxFetched = GStorage.setting.get(inboxFetchedKey) == true;
      if (!hasInboxFetched) {
        final detailResult = await FeedHttp.getInboxEntryDetail(
          entryId: article.entryId,
        );
        if (detailResult is Success<String> &&
            detailResult.response.isNotEmpty &&
            AccountSessionGuard.isCurrent(accountRevision)) {
          rawContent = detailResult.response;
          processedArticle = ArticleModel(
            entryId: article.entryId,
            feedId: article.feedId,
            feedTitle: article.feedTitle,
            feedImage: article.feedImage,
            title: article.title,
            url: article.url,
            content: rawContent,
            publishedAt: article.publishedAt,
            isRead: article.isRead,
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
          LocalArticleDbService.upsertOne(processedArticle);
          ArticleContentUtils.clearCacheForEntry(article.entryId);
          GStorage.setting.put(inboxFetchedKey, true);
        }
      }
    }

    // 检查是否需要去抓取长文
    final isManualForced =
        FeedReadabilitySettingsService.isAutoReadabilityEnabled(article.feedId);

    // 成功标记：仅在成功解析并持久化有效正文后写入。
    final hasSucceeded =
        GStorage.setting.get(_fetchedKey(article.entryId)) == true;
    // 失败诊断状态（旧版本在请求前就写标记，正文为空或明确失败时
    // 按兼容语义进入有限次重试；已有非空正文的旧标记文章不再重抓）。
    final failedState = GStorage.setting.get(_stateKey(article.entryId));
    final emptyContentCompat = hasSucceeded && rawContent.trim().isEmpty;

    if (isManualForced &&
        article.url.isNotEmpty &&
        (!hasSucceeded || emptyContentCompat || failedState != null)) {
      if (!AccountSessionGuard.isCurrent(accountRevision)) return;
      final fetched = await _fetchLongForm(
        article,
        rawContent,
        accountRevision,
      );
      if (fetched != null) {
        processedArticle = fetched;
        rawContent = fetched.content ?? rawContent;
      }
    }

    if (!AccountSessionGuard.isCurrent(accountRevision)) return;
    // 过滤保持原有行为；自动 AI 调度统一按最新持久化状态判断，避免
    // 上游队列中的旧未读快照在标记已读后重新入队。已开始的抓取流水线
    // 即使完成前被标为已读，也继续进入翻译和摘要（allowRead）。
    AutoFilterWorker.enqueue(processedArticle);
    AutoAiQueueCoordinator.onArticleContentAvailable(
      processedArticle,
      allowRead: true,
    );
  }

  /// 抓取全文并持久化。仅在成功解析且有效正文比摘要更长时写入成功标记。
  /// 返回更新后的文章；失败或正文未变长时返回 null 并登记失败状态。
  static Future<ArticleModel?> _fetchLongForm(
    ArticleModel article,
    String rawContent,
    int accountRevision,
  ) async {
    final entryId = article.entryId;
    String html;
    try {
      final override = debugFetchOverride;
      if (override != null) {
        final result = await override(article);
        if (result == null) {
          _markFetchFailure(entryId, 'fetch returned no content');
          return null;
        }
        html = result;
      } else {
        final response = await Request.dio.get(article.url);
        html = response.data.toString();
      }
      // 抓取完成后再校验账号会话：过期会话不得解析/持久化结果。
      if (!AccountSessionGuard.isCurrent(accountRevision)) return null;

      final document = html_parser.parse(html);
      final node = ArticleContentUtils.getReadabilityContent(document);
      if (node == null) {
        _markFetchFailure(entryId, 'no readability content parsed');
        return null;
      }
      final newHtml = node.outerHtml;
      // 只有当抓取到的长文确实比摘要长时，才替换并入库
      if (newHtml.length <= rawContent.length) {
        _markFetchFailure(entryId, 'parsed content is not longer than summary');
        return null;
      }

      final processedArticle = ArticleModel(
        entryId: article.entryId,
        feedId: article.feedId,
        feedTitle: article.feedTitle,
        feedImage: article.feedImage,
        title: article.title,
        url: article.url,
        content: newHtml, // 替换长文
        publishedAt: article.publishedAt,
        isRead: article.isRead,
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
      // 将包含长文的新文章存入本地数据库
      LocalArticleDbService.upsertOne(processedArticle);
      // 清除之前的缓存，保证后续 AI 用到最新的解析内容
      ArticleContentUtils.clearCacheForEntry(article.entryId);
      _markFetchSuccess(entryId);
      return processedArticle;
    } catch (e) {
      _markFetchFailure(entryId, e.toString());
      return null;
    }
  }

  static String _fetchedKey(String entryId) => 'readability_fetched_$entryId';

  static String _stateKey(String entryId) => '$_fetchStateKeyPrefix$entryId';

  static Map<String, dynamic>? _fetchStateOf(String entryId) {
    final raw = GStorage.setting.get(_stateKey(entryId));
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  /// 登记一次抓取失败：记录可诊断状态并安排有限次数 + 指数退避的重试。
  static void _markFetchFailure(String entryId, String error) {
    final previous = _fetchStateOf(entryId);
    final attempts = ((previous?['attempts'] as int?) ?? 0) + 1;
    unawaited(
      GStorage.setting.put(_stateKey(entryId), {
        'attempts': attempts,
        'lastError': error.length > 200 ? error.substring(0, 200) : error,
        'lastAt': DateTime.now().millisecondsSinceEpoch,
      }),
    );
    debugPrint(
      '[Readability] fetch failed for $entryId (attempt $attempts): $error',
    );
    _scheduleFetchRetry(entryId, attempts);
  }

  /// 有限次数自动重试：退避后重新入队；达到上限后停止并保留失败状态。
  static void _scheduleFetchRetry(String entryId, int attempts) {
    _fetchRetryTimers.remove(entryId)?.cancel();
    if (attempts > _maxFetchRetryAttempts) return;
    final backoff = _fetchRetryBackoffs[attempts - 1];
    _fetchRetryTimers[entryId] = Timer(backoff, () {
      _fetchRetryTimers.remove(entryId);
      if (_running.contains(entryId)) return;
      final raw = GStorage.articleDb.get(entryId);
      if (raw is! Map) return;
      final article = ArticleModel.fromCache(Map<String, dynamic>.from(raw));
      if (article.isRead) return; // 等待期间被标为已读 → 取消重试
      enqueueOne(article);
    });
  }

  /// 成功抓取并持久化有效正文后写入成功标记，清除失败状态。
  static void _markFetchSuccess(String entryId) {
    _fetchRetryTimers.remove(entryId)?.cancel();
    unawaited(GStorage.setting.put(_fetchedKey(entryId), true));
    unawaited(GStorage.setting.delete(_stateKey(entryId)));
  }

  static void cancelProcessing() {
    for (final timer in _fetchRetryTimers.values) {
      timer.cancel();
    }
    _fetchRetryTimers.clear();
    _queue.clear();
    _queuedIds.clear();
    _running.clear();
  }
}
