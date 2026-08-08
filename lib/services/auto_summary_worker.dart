import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../models/article.dart';
import 'llm_config.dart';
import 'summary_service.dart';
import 'article_relation_service.dart';

/// 后台自动摘要任务队列 — 滚动补位调度
///
/// 独立于翻译/过滤 worker：独立队列、独立并发配置（[LlmConfig.loadSummary]）
/// 与独立生命周期。任务完成后立即补位，运行中数量始终不超过并发配置。
abstract final class AutoSummaryWorker {
  static final _queue = <ArticleModel>[];
  static final _running = <String>{};
  static int _generation = 0;
  static Timer? _processingTimer;
  static const Duration _processingInterval = Duration(milliseconds: 500);
  static final processingCount = 0.obs;

  /// 并发数按需读取，运行中修改会在后续补位时生效。
  static int get _concurrency => LlmConfig.loadSummary().concurrency;

  /// 测试注入点：替换实际摘要调用，避免测试触发真实网络请求。
  @visibleForTesting
  static Future<void> Function(ArticleModel article)? debugRunOverride;

  /// 排队文章自动摘要（对所有未摘要的文章）
  static void enqueueIfNeeded(ArticleModel article) {
    if (article.entryId.isEmpty) return;
    if (SummaryService.hasSummary(article.entryId)) return;
    final content = (article.content ?? '').trim();
    if (content.isEmpty) return;

    if (_running.contains(article.entryId)) return;
    if (!_queue.any((a) => a.entryId == article.entryId)) {
      _queue.add(article);
    }

    _ensureProcessing();
  }

  /// 排队多篇文章
  static void enqueueIfNeededMany(List<ArticleModel> articles) {
    for (final article in articles) {
      enqueueIfNeeded(article);
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
  static void _pump() {
    while (_running.length < _concurrency && _queue.isNotEmpty) {
      final article = _queue.removeAt(0);
      _start(article);
    }
    _stopTimerIfIdle();
  }

  static void _start(ArticleModel article) {
    final generation = _generation;
    _running.add(article.entryId);
    processingCount.value = _running.length;
    unawaited(
      _runTask(article).whenComplete(() {
        if (generation != _generation) return;
        _running.remove(article.entryId);
        processingCount.value = _running.length;
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
    try {
      await SummaryService.summarizeArticle(article, deferRelationTail: true);
    } catch (e) {
      // 静默处理
    }
  }

  static void _stopTimerIfIdle() {
    if (_queue.isNotEmpty || _running.isNotEmpty) return;
    _processingTimer?.cancel();
    _processingTimer = null;
    ArticleRelationService.notifySummaryQueueIdle();
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
    processingCount.value = 0;
  }
}
