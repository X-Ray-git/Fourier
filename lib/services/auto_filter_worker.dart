import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../models/article.dart';
import '../utils/storage.dart';
import 'account_session_guard.dart';
import 'analysis_event_ledger.dart';
import 'article_filter_service.dart';
import 'article_state_notifier.dart';
import 'llm_config.dart';
import 'local_article_db_service.dart';

/// 后台 AI 过滤任务队列 — 滚动补位调度
///
/// 独立于翻译/摘要 worker：独立队列、独立并发配置（[LlmConfig.loadFilter]）
/// 与独立生命周期。任务完成后立即补位，运行中数量始终不超过并发配置。
/// 已读 / 已判 / 已捞回的文章在出队时按最新持久化状态跳过。
abstract final class AutoFilterWorker {
  static final _queue = <ArticleModel>[];
  static final _running = <String>{};
  static int _generation = 0;
  static Timer? _processingTimer;
  static const Duration _processingInterval = Duration(milliseconds: 500);

  /// 并发数按需读取，运行中修改会在后续补位时生效。
  static int get _concurrency => LlmConfig.loadFilter().concurrency;

  /// 队列中剩余
  static final queuedCount = 0.obs;

  /// 正在处理中
  static final processingCount = 0.obs;

  /// 已完成（含成功和失败）
  static final doneCount = 0.obs;

  /// 增量回调：审核页在前台时直接推送被拒文章
  static void Function(String entryId, String title, String reason)? onRejected;

  /// 测试注入点：替换实际过滤调用，避免测试触发真实网络请求。
  @visibleForTesting
  static Future<void> Function(ArticleModel article)? debugRunOverride;

  /// 排队文章 AI 过滤
  static void enqueue(ArticleModel article) {
    if (article.entryId.isEmpty) return;
    final local = GStorage.articleDb.get(article.entryId);
    if (local is Map) {
      if (local['filterReviewed'] == true) return;
      if (local['isRejectedByAi'] == true) return;
    }
    if (article.isRejectedByAi) return;
    if (article.filterReviewed) return;
    if (article.isRead) return;
    if (article.content == null || article.content!.trim().isEmpty) return;
    if (_running.contains(article.entryId)) return;
    if (!_queue.any((a) => a.entryId == article.entryId)) {
      _queue.add(article);
      queuedCount.value = _queue.length;
    }

    _ensureProcessing();
  }

  static void enqueueMany(List<ArticleModel> articles) {
    for (final a in articles) {
      enqueue(a);
    }
  }

  static void _ensureProcessing() {
    if (_processingTimer != null && _processingTimer!.isActive) {
      // 立即补位，不等待周期定时器。
      _pump();
      return;
    }
    _processingTimer = Timer.periodic(_processingInterval, (_) => _pump());
    _pump();
  }

  /// 滚动补位：运行中数量小于并发配置且队列非空时立即启动新任务。
  /// 出队时按最新持久化状态跳过已读 / 已判定文章。
  static void _pump() {
    while (_running.length < _concurrency && _queue.isNotEmpty) {
      final article = _queue.removeAt(0);
      if (_isStale(article)) continue;
      _start(article);
    }
    queuedCount.value = _queue.length;
    _stopTimerIfIdle();
  }

  static bool _isStale(ArticleModel article) {
    final local = GStorage.articleDb.get(article.entryId);
    if (local is Map) {
      if (local['isRead'] == true) return true;
      if (local['filterReviewed'] == true) return true;
      if (local['isRejectedByAi'] == true) return true;
    }
    return article.isRead;
  }

  static void _start(ArticleModel article) {
    final generation = _generation;
    _running.add(article.entryId);
    processingCount.value = _running.length;
    doneCount.value = 0;
    unawaited(
      _runTask(article).whenComplete(() {
        if (generation != _generation) return;
        _running.remove(article.entryId);
        processingCount.value = _running.length;
        queuedCount.value = _queue.length;
        doneCount.value++;
        _pump();
      }),
    );
  }

  static Future<void> _runTask(ArticleModel article) async {
    final override = debugRunOverride;
    if (override != null) {
      await override(article);
      return;
    }
    await _filterArticle(article);
  }

  static Future<void> _filterArticle(ArticleModel article) async {
    final accountRevision = AccountSessionGuard.revision;
    try {
      if (article.isRead) return; // 处理前再检查一次
      final result = await ArticleFilterService.filterArticle(article);
      if (!AccountSessionGuard.isCurrent(accountRevision)) return;
      if (article.isRead) return; // 处理中可能被标已读

      if (result.shouldReject) {
        final updated = ArticleModel(
          entryId: article.entryId,
          feedId: article.feedId,
          feedTitle: article.feedTitle,
          feedImage: article.feedImage,
          title: article.title,
          url: article.url,
          content: article.content,
          publishedAt: article.publishedAt,
          isRead: article.isRead,
          category: article.category,
          subscriptionCategory: article.subscriptionCategory,
          author: article.author,
          imageUrl: article.imageUrl,
          isRejectedByAi: true,
          filterReason: result.reason,
          filterReviewed: article.filterReviewed,
          filteredAt: DateTime.now().millisecondsSinceEpoch,
          userAction: article.userAction,
        );
        LocalArticleDbService.upsertOne(updated);
        ArticleStateNotifier.tick(article.entryId);
        AnalysisEventLedger.recordAiClassification(
          article: updated,
          shouldReject: true,
          reason: result.reason,
          after: AnalysisEventLedger.stateSnapshotOf(updated),
        );
        // 增量推送：审核页在前台时直接追加
        onRejected?.call(article.entryId, article.title, result.reason);
      } else {
        // AI 判定保留 → 标记已审核，避免重复入队
        if (article.filterReviewed) return;
        final raw = GStorage.articleDb.get(article.entryId);
        if (raw is Map) {
          raw['filterReviewed'] = true;
          raw['isRejectedByAi'] = false;
          GStorage.articleDb.put(article.entryId, raw);
          AnalysisEventLedger.recordAiClassification(
            article: article,
            shouldReject: false,
            after: AnalysisEventLedger.stateSnapshotOf(
              ArticleModel.fromCache(Map<String, dynamic>.from(raw)),
            ),
          );
          // Kept
        }
      }
    } catch (e) {
      // Failed silently
    }
  }

  static void _stopTimerIfIdle() {
    if (_queue.isNotEmpty || _running.isNotEmpty) return;
    _processingTimer?.cancel();
    _processingTimer = null;
  }

  static int get queueSize => _queue.length;

  /// 运行中数量（测试与状态展示用）
  static int get runningCount => _running.length;

  static void cancelProcessing() {
    _generation++;
    _processingTimer?.cancel();
    _processingTimer = null;
    _queue.clear();
    _running.clear();
    queuedCount.value = 0;
    processingCount.value = 0;
    doneCount.value = 0;
  }

  /// 清除单篇文章的过滤状态（用户捞回）
  static void unReject(String entryId, {String? userAction}) {
    if (entryId.isEmpty) return;
    LocalArticleDbService.clearFilterState(entryId, userAction: userAction);
    ArticleStateNotifier.tick(entryId);
  }
}
