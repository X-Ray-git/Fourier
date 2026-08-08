import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../models/article.dart';
import 'llm_config.dart';
import 'translation_service.dart';
import 'feed_translation_settings_service.dart';

/// 后台自动翻译任务队列 — 滚动补位调度
///
/// 与 [AutoSummaryWorker]、[AutoFilterWorker] 各自独立：独立的队列、
/// 独立的并发配置（[LlmConfig.loadTranslate]）与独立的生命周期。
/// 任何任务完成后立即补充一个新任务，运行中数量始终不超过并发配置；
/// 动态修改并发数在下次补位时生效，不中断正在运行的任务。
abstract final class AutoTranslationWorker {
  static final _queue = <ArticleModel>[];
  static final _running = <String>{};
  static Timer? _processingTimer;
  static const Duration _processingInterval = Duration(milliseconds: 500);
  static final processingCount = 0.obs;

  /// 并发数按需读取，运行中修改会在后续补位时生效。
  static int get _concurrency => LlmConfig.loadTranslate().concurrency;

  /// 测试注入点：替换实际翻译调用，避免测试触发真实网络请求。
  @visibleForTesting
  static Future<void> Function(ArticleModel article)? debugRunOverride;

  /// 排队文章自动翻译（如果该feed启用了自动翻译）
  static void enqueueIfEnabled(ArticleModel article) {
    if (article.feedId.isEmpty) return;
    if (TranslationService.hasTranslation(article.entryId)) return;
    if (TranslationService.isPending(article.entryId)) return;
    final content = (article.content ?? '').trim();
    if (content.isEmpty) return;
    if (!FeedTranslationSettingsService.isAutoTranslateEnabled(
      article.feedId,
    )) {
      return;
    }

    if (_running.contains(article.entryId)) return;
    if (!_queue.any((a) => a.entryId == article.entryId)) {
      _queue.add(article);
      // 写入 pending 状态，让列表卡片立即显示翻译中动画
      TranslationService.ensureHydrated();
      if (!TranslationService.hasTranslation(article.entryId)) {
        TranslationService.markPending(article.entryId);
      }
      debugPrint('[AutoTranslation] enqueued: ${article.title}');
    }

    _ensureProcessing();
  }

  /// 排队多篇文章
  static void enqueueIfEnabledMany(List<ArticleModel> articles) {
    for (final article in articles) {
      enqueueIfEnabled(article);
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

  /// 滚动补位：只要运行中数量小于并发配置且队列非空，就立即启动新任务。
  static void _pump() {
    while (_running.length < _concurrency && _queue.isNotEmpty) {
      final article = _queue.removeAt(0);
      _start(article);
    }
    _stopTimerIfIdle();
  }

  static void _start(ArticleModel article) {
    _running.add(article.entryId);
    processingCount.value = _running.length;
    unawaited(
      _runTask(article).whenComplete(() {
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
      await TranslationService.translateArticle(article, targetLang: '简体中文');
      debugPrint('[AutoTranslation] Done: ${article.title}');
    } catch (e) {
      debugPrint('[AutoTranslation] Failed: ${article.title}: $e');
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
    _processingTimer?.cancel();
    _processingTimer = null;
    _queue.clear();
    _running.clear();
    processingCount.value = 0;
  }
}
