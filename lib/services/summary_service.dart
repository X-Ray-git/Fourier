import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart' hide Response;

import '../models/article.dart';
import '../utils/article_content_utils.dart';
import '../utils/storage.dart';
import 'llm_config.dart';
import 'llm_usage_ledger.dart';
import 'account_session_guard.dart';
import 'article_relation_service.dart';
import 'article_visual_context_service.dart';
import 'llm_multimodal_protocol.dart';

enum SummaryStatus { idle, pending, done, error }

class SummaryRecord {
  final SummaryStatus status;
  final String? summaryText;
  final String? errorMessage;
  final int updatedAt;

  const SummaryRecord({
    required this.status,
    this.summaryText,
    this.errorMessage,
    required this.updatedAt,
  });

  bool get isPending => status == SummaryStatus.pending;
  bool get isSummarized => status == SummaryStatus.done;

  SummaryRecord copyWith({
    SummaryStatus? status,
    String? summaryText,
    String? errorMessage,
    int? updatedAt,
  }) {
    return SummaryRecord(
      status: status ?? this.status,
      summaryText: summaryText ?? this.summaryText,
      errorMessage: errorMessage,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'status': status.name,
    'summaryText': summaryText,
    'errorMessage': errorMessage,
    'updatedAt': updatedAt,
  };

  factory SummaryRecord.fromJson(Map<dynamic, dynamic> json) {
    final statusName = json['status'] as String? ?? SummaryStatus.done.name;
    final status = SummaryStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => SummaryStatus.done,
    );
    return SummaryRecord(
      status: status,
      summaryText: json['summaryText'] as String?,
      errorMessage: json['errorMessage'] as String?,
      updatedAt:
          json['updatedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}

abstract final class SummaryService {
  static const String _apiBase = 'https://api.deepseek.com';
  static const Duration _timeout = Duration(seconds: 300);

  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _apiBase,
      connectTimeout: _timeout,
      receiveTimeout: _timeout,
      sendTimeout: _timeout,
    ),
  );

  @visibleForTesting
  static Future<Response<dynamic>> Function(
    String path, {
    Object? data,
    Options? options,
  })?
  debugPostOverride;

  // Keep the data map non-reactive. Reading one entry from an RxMap registers
  // the whole map as a dependency, so a summary update for any other article
  // would rebuild the currently open article's HTML subtree.
  static final Map<String, SummaryRecord> _records = {};
  static final recordsVersion = 0.obs;
  static final Map<String, RxInt> _recordVersions = {};
  static final Map<String, Future<SummaryRecord>> _inFlight = {};
  static bool _hydrated = false;
  static String? _apiKey;

  static void setApiKey(String key) => _apiKey = key.trim();

  static String? getApiKey() =>
      _apiKey ?? (GStorage.setting.get('deepseek_api_key') as String?);

  static String getPrompt(String targetLang) {
    final template = GStorage.setting.get(
      'summary_prompt',
      defaultValue: _defaultPrompt,
    ) as String;
    return template.replaceAll('{targetLang}', targetLang);
  }

  static Future<void> setPrompt(String prompt) async {
    await GStorage.setting.put('summary_prompt', prompt);
  }

  static void resetPrompt() {
    GStorage.setting.delete('summary_prompt');
  }

  static const String _defaultPrompt = '''
你是一个专业的文章摘要助手。请用{targetLang}生成一个简洁的文章摘要。

要求：
1. 摘要应该抓住文章的核心观点和重要信息
2. 如果原文内容较长，请控制在一到两句话，约 100-300 字
3. 如果原文极短（如推文），请保持摘要同样简短，绝对不能超过原文长度
4. 禁止自行发散或补充文字与图片中均未提及的细节
''';

  static void ensureHydrated() {
    if (_hydrated) return;
    final box = GStorage.summaries;
    for (final key in box.keys.cast<String>()) {
      final value = box.get(key);
      if (value is Map) {
        _records[key] = SummaryRecord.fromJson(value.cast<dynamic, dynamic>());
      } else if (value is String && value.isNotEmpty) {
        _records[key] = SummaryRecord(
          status: SummaryStatus.done,
          summaryText: value,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
      }
    }
    _hydrated = true;
  }

  /// Reactive version for exactly one article's summary record.
  ///
  /// Callers that render a record inside [Obx] should observe this value and
  /// then call [recordOf]. They will not be invalidated by another article's
  /// summary task.
  static RxInt versionFor(String entryId) {
    return _recordVersions.putIfAbsent(entryId, () => 0.obs);
  }

  static void _notifyRecordChanged(String entryId) {
    versionFor(entryId).value++;
    recordsVersion.value++;
  }

  static SummaryRecord? recordOf(String entryId) {
    try {
      ensureHydrated();
    } catch (e) {
      debugPrint('[Summary] hydrate skipped: $e');
    }
    return _records[entryId];
  }

  static SummaryStatus statusOf(String entryId) {
    return recordOf(entryId)?.status ?? SummaryStatus.idle;
  }

  static bool isPending(String entryId) =>
      statusOf(entryId) == SummaryStatus.pending;

  static bool hasSummary(String entryId) =>
      statusOf(entryId) == SummaryStatus.done;

  static int countByStatus(SummaryStatus status) {
    ensureHydrated();
    recordsVersion.value;
    return _records.values.where((record) => record.status == status).length;
  }

  static Map<String, SummaryRecord> recordsByStatus(SummaryStatus status) {
    ensureHydrated();
    recordsVersion.value;
    return Map.unmodifiable(
      Map.fromEntries(
        _records.entries.where((entry) => entry.value.status == status),
      ),
    );
  }

  static String? summaryFor(String entryId) {
    final record = recordOf(entryId);
    return record?.summaryText;
  }

  static Future<SummaryRecord> summarizeArticle(
    ArticleModel article, {
    String targetLang = '简体中文',
    String? overrideContent,
    bool deferRelationTail = false,
  }) {
    ensureHydrated();
    final existing = _inFlight[article.entryId];
    if (existing != null) return existing;

    final accountRevision = AccountSessionGuard.revision;
    final future = _summarizeArticleInternal(
      article,
      targetLang,
      overrideContent,
      accountRevision,
      deferRelationTail,
    );
    _inFlight[article.entryId] = future;
    void clearInFlight() {
      if (identical(_inFlight[article.entryId], future)) {
        _inFlight.remove(article.entryId);
      }
    }

    future.then<void>(
      (_) => clearInFlight(),
      onError: (Object _, StackTrace _) => clearInFlight(),
    );
    return future;
  }

  static Future<SummaryRecord> _summarizeArticleInternal(
    ArticleModel article,
    String targetLang,
    String? overrideContent,
    int accountRevision,
    bool deferRelationTail,
  ) async {
    final apiKey = getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError('DeepSeek API key not configured');
    }

    final previous = recordOf(article.entryId);
    // pending 只写内存，不落盘
    _records[article.entryId] =
        (previous ??
                SummaryRecord(
                  status: SummaryStatus.idle,
                  updatedAt: DateTime.now().millisecondsSinceEpoch,
                ))
            .copyWith(
              status: SummaryStatus.pending,
              errorMessage: null,
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            );
    _notifyRecordChanged(article.entryId);

    final htmlContent = ArticleContentUtils.normalizeHtmlForEntry(
      article.entryId,
      overrideContent ?? article.content ?? '',
      sourceUrl: article.url,
      feedId: article.feedId,
      category: article.category,
    );
    if (htmlContent.isEmpty) {
      final record = SummaryRecord(
        status: SummaryStatus.error,
        errorMessage: '文章内容为空，无法生成摘要',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      _writeRecord(article.entryId, record, accountRevision: accountRevision);
      return record;
    }

    final visualContext = ArticleVisualContextService.prepare(
      article,
      htmlContent,
    );
    final articlePayload =
        '标题：\n${article.title}\n\nHTML：\n<html>$htmlContent</html>\n\n'
        '${visualContext.structureMetadata}';

    final systemPrompt = getPrompt(targetLang);
    final maxRetries =
        GStorage.setting.get('auto_retry_max_count', defaultValue: 3) as int;
    final totalAttempts = maxRetries > 0 ? maxRetries + 1 : 1;
    List<String>? inlineImages;

    for (int attempt = 1; attempt <= totalAttempts; attempt++) {
      final llmConfig = LlmConfig.loadSummary();
      try {
        final parsed = await _requestJson(
          apiKey: apiKey,
          articleId: article.entryId,
          attempt: attempt,
          accountRevision: accountRevision,
          config: llmConfig,
          businessPrompt: systemPrompt,
          protocol: LlmMultimodalProtocol.summaryText,
          messages: LlmMultimodalProtocol.textMessages(
            protocol: LlmMultimodalProtocol.summaryText,
            businessPrompt: systemPrompt,
            articlePayload: articlePayload,
          ),
        );
        final textSummary = _summaryFromJson(parsed);
        final handoffValue = parsed['needs_visual_context'];
        final needsVisualContext =
            visualContext.hasImages &&
            (handoffValue is bool ? handoffValue : true);
        var finalSummary = textSummary;

        if (needsVisualContext) {
          final visionConfig = LlmMultimodalProtocol.visionConfig(
            llmConfig,
            visionModel: LlmConfig.loadSummaryVisionModel(),
          );
          try {
            inlineImages ??= await ArticleVisualContextService.loadInlineImages(
              article.entryId,
              visualContext.imageUrls,
            );
            if (!AccountSessionGuard.isCurrent(accountRevision)) {
              throw const _StaleAccountOperation();
            }
            final visionParsed = await _requestJson(
              apiKey: apiKey,
              articleId: article.entryId,
              attempt: attempt,
              accountRevision: accountRevision,
              config: visionConfig,
              businessPrompt: systemPrompt,
              protocol: LlmMultimodalProtocol.summaryVision,
              messages: LlmMultimodalProtocol.visionMessages(
                protocol: LlmMultimodalProtocol.summaryVision,
                businessPrompt: systemPrompt,
                articlePayload: articlePayload,
                imageUrls: inlineImages,
              ),
            );
            finalSummary = _summaryFromJson(visionParsed);
          } catch (error) {
            if (error is _StaleAccountOperation ||
                !AccountSessionGuard.isCurrent(accountRevision)) {
              rethrow;
            }
            if (attempt < totalAttempts) rethrow;
            debugPrint(
              '[Summary] Vision fallback failed for ${article.entryId}; '
              'using the text-only result.',
            );
          }
        }

        final record = SummaryRecord(
          status: SummaryStatus.done,
          summaryText: finalSummary,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
        await _writeCompletedRecord(
          article,
          record,
          accountRevision: accountRevision,
          deferRelationTail: deferRelationTail,
        );
        return record;
      } catch (e) {
        if (e is _StaleAccountOperation ||
            !AccountSessionGuard.isCurrent(accountRevision)) {
          rethrow;
        }
        if (attempt < totalAttempts) {
          debugPrint(
            '[Summary] Attempt $attempt failed for ${article.entryId}, retrying in 1s...',
          );
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }

        String errorMessage;
        if (e is DioException) {
          errorMessage = e.message ?? 'DeepSeek request failed';
        } else if (e is FormatException) {
          errorMessage = e.message;
        } else if (e is StateError) {
          errorMessage = e.message;
        } else {
          errorMessage = e.toString();
        }

        _restoreAfterFailure(
          article.entryId,
          previous,
          errorMessage,
          accountRevision,
        );
        return SummaryRecord(
          status: SummaryStatus.error,
          errorMessage: errorMessage,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
      }
    }

    return SummaryRecord(
      status: SummaryStatus.error,
      errorMessage: '重试次数已用尽',
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<Map<String, dynamic>> _requestJson({
    required String apiKey,
    required String articleId,
    required int attempt,
    required int accountRevision,
    required LlmConfig config,
    required String businessPrompt,
    required String protocol,
    required List<Map<String, dynamic>> messages,
  }) async {
    final requestBody = <String, dynamic>{
      'messages': messages,
      'response_format': {'type': 'json_object'},
      'stream': false,
      ...config.toRequestBody(),
    };
    final trace = LlmRequestTrace(
      task: LlmTaskType.summary,
      config: config,
      prompt: LlmMultimodalProtocol.tracePrompt(protocol, businessPrompt),
      articleId: articleId,
      attempt: attempt,
    );

    try {
      final options = Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
      );
      final postOverride = debugPostOverride;
      final response = postOverride != null
          ? await postOverride(
              '/chat/completions',
              data: requestBody,
              options: options,
            )
          : await _dio.post(
              '/chat/completions',
              data: requestBody,
              options: options,
            );
      await trace.recordResponse(
        response.data,
        httpStatus: response.statusCode,
      );
      if (!AccountSessionGuard.isCurrent(accountRevision)) {
        throw const _StaleAccountOperation();
      }

      final content = _extractMessageContent(response.data);
      if (content == null || content.trim().isEmpty) {
        throw StateError('DeepSeek returned an empty summary result');
      }

      Map<String, dynamic> parsed;
      try {
        parsed =
            jsonDecode(_normalizeJsonPayload(content)) as Map<String, dynamic>;
      } on FormatException {
        final recovered = _extractJsonObject(content);
        if (recovered == null) rethrow;
        parsed = recovered;
      }
      await trace.complete();
      return parsed;
    } catch (error) {
      await trace.fail(error);
      rethrow;
    }
  }

  static String _summaryFromJson(Map<String, dynamic> parsed) {
    final summary = (parsed['summary'] ?? '').toString().trim();
    if (summary.isEmpty) {
      throw StateError('DeepSeek summary result missing summary field');
    }
    return summary;
  }

  static void deleteSummary(String entryId) {
    ensureHydrated();
    _records.remove(entryId);
    _notifyRecordChanged(entryId);
    GStorage.summaries.delete(entryId);
  }

  static void resetForAccountChange() {
    final affectedIds = <String>{..._records.keys, ..._recordVersions.keys};
    _records.clear();
    _inFlight.clear();
    _hydrated = false;
    recordsVersion.value++;
    for (final entryId in affectedIds) {
      versionFor(entryId).value++;
    }
  }

  static void _restoreAfterFailure(
    String entryId,
    SummaryRecord? previous,
    String errorMessage,
    int accountRevision,
  ) {
    if (previous != null) {
      _writeRecord(
        entryId,
        previous.copyWith(
          status: previous.isSummarized
              ? SummaryStatus.done
              : SummaryStatus.idle,
          errorMessage: errorMessage,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
        accountRevision: accountRevision,
      );
    } else {
      final record = SummaryRecord(
        status: SummaryStatus.error,
        errorMessage: errorMessage,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      _writeRecord(entryId, record, accountRevision: accountRevision);
    }
  }

  static void _writeRecord(
    String entryId,
    SummaryRecord record, {
    int? accountRevision,
  }) {
    if (accountRevision != null &&
        !AccountSessionGuard.isCurrent(accountRevision)) {
      return;
    }
    ensureHydrated();
    _records[entryId] = record;
    _notifyRecordChanged(entryId);
    GStorage.summaries.put(entryId, record.toJson());
  }

  static Future<void> _writeCompletedRecord(
    ArticleModel article,
    SummaryRecord record, {
    required int accountRevision,
    required bool deferRelationTail,
  }) async {
    if (!AccountSessionGuard.isCurrent(accountRevision)) return;
    ensureHydrated();
    _records[article.entryId] = record;
    _notifyRecordChanged(article.entryId);
    await GStorage.summaries.put(article.entryId, record.toJson());
    if (!AccountSessionGuard.isCurrent(accountRevision)) return;
    try {
      await ArticleRelationService.onSummaryCompleted(article, record);
      if (!deferRelationTail) {
        ArticleRelationService.notifySummaryQueueIdle();
      }
    } catch (error) {
      // 关系建立是摘要之上的增益功能；其存储异常不能把已成功的摘要改判为失败。
      debugPrint('[ArticleRelation] summary enqueue failed: $error');
    }
  }

  static String? _extractMessageContent(dynamic data) {
    if (data is! Map) return null;
    final choices = data['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) return null;
    final firstChoice = choices.first as Map<String, dynamic>?;
    if (firstChoice == null) return null;
    final message = firstChoice['message'];
    if (message is! Map) return null;
    return message['content'] as String?;
  }

  static String _normalizeJsonPayload(String raw) {
    var content = raw.trim();
    if (content.startsWith('```json')) {
      content = content
          .replaceFirst(RegExp(r'^```json\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '');
    } else if (content.startsWith('```')) {
      content = content
          .replaceFirst(RegExp(r'^```\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '');
    }
    final firstBrace = content.indexOf('{');
    final lastBrace = content.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      content = content.substring(firstBrace, lastBrace + 1);
    }
    return content;
  }

  static Map<String, dynamic>? _extractJsonObject(String raw) {
    final first = raw.indexOf('{');
    final last = raw.lastIndexOf('}');
    if (first < 0 || last <= first) return null;
    try {
      return jsonDecode(raw.substring(first, last + 1)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}

class _StaleAccountOperation implements Exception {
  const _StaleAccountOperation();
}
