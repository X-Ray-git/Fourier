import 'dart:async';
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

abstract final class AutoReadabilityWorker {
  static final _queue = <ArticleModel>[];
  static final _queuedIds = <String>{};
  static bool _isRunning = false;

  /// 最大并发请求数
  static const int _concurrency = 3;

  /// 入队一篇文章
  static void enqueueOne(ArticleModel article) {
    if (article.isRead) return;
    if (article.entryId.isEmpty) return;
    if (!_queuedIds.add(article.entryId)) return;
    _queue.add(article);
    _startProcessingIfNeeded();
  }

  /// 批量入队
  static void enqueueMany(List<ArticleModel> articles) {
    var added = false;
    for (final article in articles) {
      if (article.isRead || article.entryId.isEmpty) continue;
      if (!_queuedIds.add(article.entryId)) continue;
      _queue.add(article);
      added = true;
    }
    if (!added) return;
    _startProcessingIfNeeded();
  }

  static void _startProcessingIfNeeded() {
    if (_isRunning || _queue.isEmpty) return;
    _isRunning = true;
    unawaited(_processQueue());
  }

  static Future<void> _processQueue() async {
    while (_queue.isNotEmpty) {
      final count = _queue.length > _concurrency ? _concurrency : _queue.length;
      final batch = _queue.sublist(0, count);
      _queue.removeRange(0, count);

      await Future.wait(batch.map((article) => _processArticle(article)));
    }

    _isRunning = false;
    // 双重检查
    if (_queue.isNotEmpty) {
      _startProcessingIfNeeded();
    }
  }

  static Future<void> _processArticle(ArticleModel article) async {
    final accountRevision = AccountSessionGuard.revision;
    try {
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
            );
            LocalArticleDbService.upsertOne(processedArticle);
            ArticleContentUtils.clearCacheForEntry(article.entryId);
            GStorage.setting.put(inboxFetchedKey, true);
          }
        }
      }

      // 检查是否需要去抓取长文
      final isManualForced =
          FeedReadabilitySettingsService.isAutoReadabilityEnabled(
            article.feedId,
          );

      // 防重复拉取标记
      final hasFetchedKey = 'readability_fetched_${article.entryId}';
      final hasFetched = GStorage.setting.get(hasFetchedKey) == true;

      // 仅当该订阅源开启了 Readability 开关时才抓取长文
      if (!hasFetched && isManualForced && article.url.isNotEmpty) {
        if (!AccountSessionGuard.isCurrent(accountRevision)) return;
        // 立即打上标记，防止无论成功失败都反复重试
        GStorage.setting.put(hasFetchedKey, true);
        try {
          final response = await Request.dio.get(article.url);
          if (!AccountSessionGuard.isCurrent(accountRevision)) return;
          final document = html_parser.parse(response.data.toString());
          final node = ArticleContentUtils.getReadabilityContent(document);
          if (node != null) {
            final newHtml = node.outerHtml;
            // 只有当抓取到的长文确实比摘要长时，才替换并入库
            if (newHtml.length > rawContent.length) {
              processedArticle = ArticleModel(
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
              );
              // 将包含长文的新文章存入本地数据库
              LocalArticleDbService.upsertOne(processedArticle);

              // 清除之前的缓存，保证后续 AI 用到最新的解析内容
              ArticleContentUtils.clearCacheForEntry(article.entryId);
            }
          }
        } catch (_) {
          // 静默失败，沿用原有的短文
        }
      }

      if (!AccountSessionGuard.isCurrent(accountRevision)) return;
      // 过滤保持原有行为；自动 AI 调度统一按最新持久化状态判断，避免
      // 上游队列中的旧未读快照在标记已读后重新入队。
      AutoFilterWorker.enqueue(processedArticle);
      AutoAiQueueCoordinator.onArticleContentAvailable(processedArticle);
    } finally {
      if (AccountSessionGuard.isCurrent(accountRevision)) {
        _queuedIds.remove(article.entryId);
      }
    }
  }

  static void cancelProcessing() {
    _queue.clear();
    _queuedIds.clear();
  }
}
