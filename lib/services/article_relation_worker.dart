import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../models/article_relation.dart';
import '../utils/storage.dart';
import 'account_session_guard.dart';
import 'article_relation_service.dart';
import 'article_relation_prompt_service.dart';
import 'llm_config.dart';
import 'llm_usage_ledger.dart';

class ArticleRelationApiResult {
  const ArticleRelationApiResult({
    required this.groups,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.cacheHitTokens = 0,
    this.cacheMissTokens = 0,
    this.totalTokens = 0,
  });

  final List<ArticleRelationCandidateGroup> groups;
  final int promptTokens;
  final int completionTokens;
  final int cacheHitTokens;
  final int cacheMissTokens;
  final int totalTokens;
}

/// 摘要关系批处理 worker。
///
/// 固定单飞：32 是每批新摘要数量，而不是并发请求数。失败时 pending
/// 原样保留，历史窗口也不推进；用户可在任务中心重试。
abstract final class ArticleRelationWorker {
  static const Duration _timeout = Duration(seconds: 300);
  static const int _maxAttempts = 3;
  static String get promptVersion =>
      'relation-v1@${ArticleRelationPromptService.promptFingerprint}';

  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.deepseek.com',
      connectTimeout: _timeout,
      receiveTimeout: _timeout,
      sendTimeout: _timeout,
    ),
  );

  static final processingCount = 0.obs;
  static final currentNewCount = 0.obs;
  static final currentHistoryCount = 0.obs;
  static final completedThisSession = 0.obs;
  static final failedThisSession = 0.obs;
  static final lastError = RxnString();

  static bool _initialized = false;
  static bool _running = false;
  static bool _scheduled = false;
  static bool _flushPartialRequested = false;
  static bool _retryRequired = false;
  static int _generation = 0;

  @visibleForTesting
  static Future<ArticleRelationApiResult> Function(
    ArticleRelationBatchInput input,
  )?
  debugRequestOverride;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await ArticleRelationService.initialize();
    ArticleRelationService.registerScheduler(schedule);
    final failedBatch = _latestFailedPendingBatch();
    if (failedBatch != null) {
      _retryRequired = true;
      lastError.value = failedBatch.error ?? '上次关系请求失败';
      return;
    }
    if (ArticleRelationService.pendingCount >=
        ArticleRelationService.batchSize) {
      schedule(flushPartial: false);
    }
  }

  static void schedule({required bool flushPartial}) {
    if (_retryRequired) return;
    _flushPartialRequested = _flushPartialRequested || flushPartial;
    if (_running || _scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      unawaited(_pump());
    });
  }

  static void retryPending() {
    _retryRequired = false;
    lastError.value = null;
    schedule(flushPartial: true);
  }

  static Future<void> _pump() async {
    if (_running) return;
    _running = true;
    final generation = _generation;
    try {
      while (generation == _generation) {
        final flushPartial = _flushPartialRequested;
        _flushPartialRequested = false;
        final input = await ArticleRelationService.prepareNextBatch(
          flushPartial: flushPartial,
        );
        if (input == null) break;
        final ok = await _runBatch(input, generation);
        if (!ok) break;
        // 完整批次完成后立即消费下一批；不足 32 的尾批只在明确空闲时发车。
        if (ArticleRelationService.pendingCount >=
            ArticleRelationService.batchSize) {
          continue;
        }
        if (_flushPartialRequested) continue;
        break;
      }
    } finally {
      _running = false;
      processingCount.value = 0;
      currentNewCount.value = 0;
      currentHistoryCount.value = 0;
      if (_flushPartialRequested) {
        schedule(flushPartial: true);
      }
    }
  }

  static Future<bool> _runBatch(
    ArticleRelationBatchInput input,
    int generation,
  ) async {
    final accountRevision = AccountSessionGuard.revision;
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    final config = LlmConfig.loadRelation();
    processingCount.value = 1;
    currentNewCount.value = input.newNodes.length;
    currentHistoryCount.value = input.historyNodes.length;
    lastError.value = null;

    await _saveBatch(
      ArticleRelationBatchRecord(
        id: input.id,
        status: 'running',
        newArticleIds: input.newNodes.map((node) => node.articleId).toList(),
        historyArticleIds: input.historyNodes
            .map((node) => node.articleId)
            .toList(),
        model: config.model,
        promptVersion: promptVersion,
        schemaVersion: ArticleRelationService.schemaVersion,
        startedAt: startedAt,
      ),
    );

    Object? finalError;
    var expandOutputBudget = false;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final override = debugRequestOverride;
        final result = override == null
            ? await _request(
                input,
                expandOutputBudget && config.maxTokens < 32768
                    ? config.copyWith(maxTokens: 32768)
                    : config,
                attempt,
              )
            : await override(input);
        if (generation != _generation ||
            !AccountSessionGuard.isCurrent(accountRevision)) {
          return false;
        }
        await ArticleRelationService.completeBatch(input, result.groups);
        final completedAt = DateTime.now().millisecondsSinceEpoch;
        await _saveBatch(
          ArticleRelationBatchRecord(
            id: input.id,
            status: 'done',
            newArticleIds: input.newNodes
                .map((node) => node.articleId)
                .toList(),
            historyArticleIds: input.historyNodes
                .map((node) => node.articleId)
                .toList(),
            model: config.model,
            promptVersion: promptVersion,
            schemaVersion: ArticleRelationService.schemaVersion,
            startedAt: startedAt,
            completedAt: completedAt,
            groupCount: result.groups.length,
            promptTokens: result.promptTokens,
            completionTokens: result.completionTokens,
            cacheHitTokens: result.cacheHitTokens,
            cacheMissTokens: result.cacheMissTokens,
            totalTokens: result.totalTokens,
            durationMs: completedAt - startedAt,
          ),
        );
        completedThisSession.value++;
        return true;
      } catch (error) {
        finalError = error;
        if (error is _TruncatedRelationResponse) {
          expandOutputBudget = true;
        }
        if (attempt < _maxAttempts && generation == _generation) {
          await Future<void>.delayed(Duration(seconds: attempt));
        }
      }
    }

    if (generation != _generation ||
        !AccountSessionGuard.isCurrent(accountRevision)) {
      return false;
    }
    final message = _errorMessage(finalError);
    final completedAt = DateTime.now().millisecondsSinceEpoch;
    await _saveBatch(
      ArticleRelationBatchRecord(
        id: input.id,
        status: 'failed',
        newArticleIds: input.newNodes.map((node) => node.articleId).toList(),
        historyArticleIds: input.historyNodes
            .map((node) => node.articleId)
            .toList(),
        model: config.model,
        promptVersion: promptVersion,
        schemaVersion: ArticleRelationService.schemaVersion,
        startedAt: startedAt,
        completedAt: completedAt,
        error: message,
        durationMs: completedAt - startedAt,
      ),
    );
    failedThisSession.value++;
    _retryRequired = true;
    _flushPartialRequested = false;
    lastError.value = message;
    return false;
  }

  static Future<ArticleRelationApiResult> _request(
    ArticleRelationBatchInput input,
    LlmConfig config,
    int attempt,
  ) async {
    final apiKey =
        GStorage.setting.get('deepseek_api_key', defaultValue: '') as String;
    if (apiKey.trim().isEmpty) {
      throw StateError('DeepSeek API key not configured');
    }
    final labels = <String, ArticleRelationNode>{};
    for (var i = 0; i < input.newNodes.length; i++) {
      labels['N${(i + 1).toString().padLeft(3, '0')}'] = input.newNodes[i];
    }
    for (var i = 0; i < input.historyNodes.length; i++) {
      labels['H${(i + 1).toString().padLeft(3, '0')}'] = input.historyNodes[i];
    }

    final prompt = ArticleRelationPromptService.getPrompt();
    final trace = LlmRequestTrace(
      task: LlmTaskType.relation,
      config: config,
      prompt: prompt,
      batchId: input.id,
      attempt: attempt,
    );
    try {
      final response = await _dio.post(
        '/chat/completions',
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'messages': [
            {'role': 'system', 'content': prompt},
            {
              'role': 'user',
              'content': jsonEncode({
                // 稳定历史放在前缀位置，便于 DeepSeek 自动前缀缓存命中；
                // 本批变化的 new 放在最后。
                'history': [
                  for (final entry in labels.entries.where(
                    (entry) => entry.key.startsWith('H'),
                  ))
                    _nodePayload(entry.key, entry.value),
                ],
                'new': [
                  for (final entry in labels.entries.where(
                    (entry) => entry.key.startsWith('N'),
                  ))
                    _nodePayload(entry.key, entry.value),
                ],
              }),
            },
          ],
          'response_format': {'type': 'json_object'},
          'stream': false,
          ...config.toRequestBody(),
        },
      );
      await trace.recordResponse(
        response.data,
        httpStatus: response.statusCode,
      );
      final result = parseResponse(response.data, labels);
      await trace.complete();
      return result;
    } catch (error) {
      await trace.fail(error);
      rethrow;
    }
  }

  @visibleForTesting
  static ArticleRelationApiResult parseResponse(
    dynamic responseData,
    Map<String, ArticleRelationNode> labels,
  ) {
    if (responseData is! Map) {
      throw const FormatException('关系响应不是 JSON 对象');
    }
    final choices = responseData['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty || choices.first is! Map) {
      throw const FormatException('关系响应缺少 choices');
    }
    final choice = choices.first as Map;
    final finishReason = choice['finish_reason']?.toString();
    if (finishReason != null && finishReason != 'stop') {
      if (finishReason == 'length') {
        throw const _TruncatedRelationResponse();
      }
      throw FormatException('关系响应未完整结束：$finishReason');
    }
    final message = choice['message'];
    final content = message is Map ? message['content']?.toString().trim() : '';
    if (content == null || content.isEmpty) {
      throw const FormatException('关系响应内容为空');
    }
    final parsed = jsonDecode(_normalizeJson(content));
    if (parsed is! Map<String, dynamic>) {
      throw const FormatException('关系响应根节点格式错误');
    }
    final rawGroups = parsed['groups'];
    if (rawGroups is! List) {
      throw const FormatException('关系响应缺少 groups 数组');
    }
    final groups = <ArticleRelationCandidateGroup>[];
    for (final raw in rawGroups) {
      if (raw is! Map) continue;
      final memberLabels = (raw['members'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .where(labels.containsKey)
          .toSet()
          .toList(growable: false);
      if (memberLabels.length < 2 ||
          !memberLabels.any((label) => label.startsWith('N'))) {
        continue;
      }
      final reason = raw['reason']?.toString().trim() ?? '';
      final confidence = ((raw['confidence'] as num?)?.toDouble() ?? 0.5).clamp(
        0.0,
        1.0,
      );
      groups.add(
        ArticleRelationCandidateGroup(
          memberIds: memberLabels
              .map((label) => labels[label]!.articleId)
              .toList(growable: false),
          reason: reason,
          confidence: confidence,
        ),
      );
    }
    final usage = responseData['usage'];
    int token(String key) =>
        usage is Map ? (usage[key] as num?)?.toInt() ?? 0 : 0;
    return ArticleRelationApiResult(
      groups: groups,
      promptTokens: token('prompt_tokens'),
      completionTokens: token('completion_tokens'),
      cacheHitTokens: token('prompt_cache_hit_tokens'),
      cacheMissTokens: token('prompt_cache_miss_tokens'),
      totalTokens: token('total_tokens'),
    );
  }

  static Map<String, dynamic> _nodePayload(
    String id,
    ArticleRelationNode node,
  ) {
    return {
      'id': id,
      'title': node.title,
      'source': node.feedTitle,
      if ((node.author ?? '').isNotEmpty) 'author': node.author,
      if (node.publishedAt.isNotEmpty) 'published_at': node.publishedAt,
      'summary': node.summary,
    };
  }

  static String _normalizeJson(String raw) {
    var value = raw.trim();
    if (value.startsWith('```')) {
      value = value.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      value = value.replaceFirst(RegExp(r'\s*```$'), '');
    }
    final first = value.indexOf('{');
    final last = value.lastIndexOf('}');
    if (first >= 0 && last > first) return value.substring(first, last + 1);
    return value;
  }

  static Future<void> _saveBatch(ArticleRelationBatchRecord record) {
    return GStorage.relationBatches.put(record.id, record.toJson());
  }

  static ArticleRelationBatchRecord? _latestFailedPendingBatch() {
    ArticleRelationBatchRecord? latest;
    for (final value in GStorage.relationBatches.values) {
      if (value is! Map) continue;
      final record = ArticleRelationBatchRecord.fromJson(
        value.cast<dynamic, dynamic>(),
      );
      if (latest == null || record.startedAt > latest.startedAt) {
        latest = record;
      }
    }
    if (latest?.status != 'failed') return null;
    final pendingIds = ArticleRelationService.pendingArticleIds.toSet();
    return latest!.newArticleIds.any(pendingIds.contains) ? latest : null;
  }

  static String _errorMessage(Object? error) {
    if (error is DioException) return error.message ?? '关系请求失败';
    if (error is StateError) return error.message;
    if (error is FormatException) return error.message;
    return error?.toString() ?? '关系请求失败';
  }

  static void cancelProcessing() {
    _generation++;
    _scheduled = false;
    _flushPartialRequested = false;
    _retryRequired = false;
    processingCount.value = 0;
    currentNewCount.value = 0;
    currentHistoryCount.value = 0;
    lastError.value = null;
  }

  @visibleForTesting
  static void resetForTest() {
    cancelProcessing();
    _initialized = false;
    completedThisSession.value = 0;
    failedThisSession.value = 0;
    debugRequestOverride = null;
  }
}

class _TruncatedRelationResponse extends FormatException {
  const _TruncatedRelationResponse() : super('关系响应因输出上限被截断');
}
