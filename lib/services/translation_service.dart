import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../models/article.dart';
import '../utils/article_content_utils.dart';
import '../utils/html_entity_utils.dart';
import '../utils/storage.dart';
import 'llm_config.dart';
import 'llm_failure_policy.dart';
import 'llm_usage_ledger.dart';
import 'account_session_guard.dart';

enum TranslationStatus { idle, pending, done, error }

class TranslationRecord {
  final TranslationStatus status;
  final String? translatedTitle;
  final String? translatedContent;
  final String? errorMessage;
  final int updatedAt;

  const TranslationRecord({
    required this.status,
    this.translatedTitle,
    this.translatedContent,
    this.errorMessage,
    required this.updatedAt,
  });

  bool get isPending => status == TranslationStatus.pending;
  bool get isTranslated => status == TranslationStatus.done;

  TranslationRecord copyWith({
    TranslationStatus? status,
    String? translatedTitle,
    String? translatedContent,
    String? errorMessage,
    int? updatedAt,
  }) {
    return TranslationRecord(
      status: status ?? this.status,
      translatedTitle: translatedTitle ?? this.translatedTitle,
      translatedContent: translatedContent ?? this.translatedContent,
      errorMessage: errorMessage,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'status': status.name,
    'translatedTitle': translatedTitle,
    'translatedContent': translatedContent,
    'errorMessage': errorMessage,
    'updatedAt': updatedAt,
  };

  factory TranslationRecord.fromJson(Map<dynamic, dynamic> json) {
    final statusName = json['status'] as String? ?? TranslationStatus.done.name;
    final status = TranslationStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => TranslationStatus.done,
    );
    return TranslationRecord(
      status: status,
      translatedTitle: HtmlEntityUtils.decodeNullableText(
        json['translatedTitle'] as String?,
      ),
      translatedContent: json['translatedContent'] as String?,
      errorMessage: json['errorMessage'] as String?,
      updatedAt:
          json['updatedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}

abstract final class TranslationService {
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

  // Reading a value from an RxMap subscribes the caller to the whole map.
  // Keep records plain and expose per-entry versions so an unrelated
  // translation cannot rebuild every article card.
  static final Map<String, TranslationRecord> _records = {};
  static final recordsVersion = 0.obs;
  static final Map<String, RxInt> _recordVersions = {};
  static final Map<String, Future<TranslationRecord>> _inFlight = {};
  static bool _hydrated = false;
  static String? _apiKey;

  @visibleForTesting
  static Future<void> Function(Duration duration)? debugRetryDelayOverride;

  static void setApiKey(String key) => _apiKey = key.trim();

  static String? getApiKey() =>
      _apiKey ?? (GStorage.setting.get('deepseek_api_key') as String?);

  static String getPrompt(String targetLang) {
    final template = GStorage.setting.get(
      'translation_prompt',
      defaultValue: _defaultPrompt,
    ) as String;
    return template.replaceAll('{targetLang}', targetLang);
  }

  static Future<void> setPrompt(String prompt) async {
    await GStorage.setting.put('translation_prompt', prompt);
  }

  static void resetPrompt() {
    GStorage.setting.delete('translation_prompt');
  }

  static const String _defaultPrompt = '''
你是一个专业的文章翻译助手。请将文章翻译成{targetLang}。

要求：
1. 只返回 JSON，不要返回 markdown、解释或代码块
2. 具体 JSON 结构以 User Prompt 中的要求为准
3. translated_title 为翻译后的标题
4. translated_html 必须保留所有 HTML 标签、结构、属性、空白和排版
5. 只翻译可见文本，不要改动任何 HTML 标签
6. 你无法读取图片内容。请仅基于提供的文本翻译；如果有强依赖图片的上下文，请根据文本合理处理，不要编造图片细节。
''';

  static void ensureHydrated() {
    if (_hydrated) return;
    final box = GStorage.translations;
    var staleCount = 0;
    for (final key in box.keys.cast<String>()) {
      final value = box.get(key);
      if (value is Map) {
        final record = TranslationRecord.fromJson(
          value.cast<dynamic, dynamic>(),
        );
        // 清理残留的 pending 状态（App 被杀/崩溃导致）
        if (record.status == TranslationStatus.pending) {
          staleCount++;
          box.delete(key); // 从磁盘移除旧版残留，后续 pending 不再落盘
          _records[key] = record.copyWith(status: TranslationStatus.idle);
        } else {
          _records[key] = record;
        }
      } else if (value is String && value.isNotEmpty) {
        _records[key] = TranslationRecord(
          status: TranslationStatus.done,
          translatedContent: _cleanTranslatedContent(value),
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
      }
    }
    if (staleCount > 0) {
      debugPrint('[Translation] 清理了 $staleCount 条残留 pending 记录');
    }
    _hydrated = true;
  }

  /// Reactive version for exactly one article's translation record.
  static RxInt versionFor(String entryId) {
    return _recordVersions.putIfAbsent(entryId, () => 0.obs);
  }

  static void _notifyRecordChanged(String entryId) {
    versionFor(entryId).value++;
    recordsVersion.value++;
  }

  static TranslationRecord? recordOf(String entryId) {
    try {
      ensureHydrated();
    } catch (e) {
      debugPrint('[Translation] hydrate skipped: $e');
    }
    return _records[entryId];
  }

  static TranslationStatus statusOf(String entryId) {
    return recordOf(entryId)?.status ?? TranslationStatus.idle;
  }

  static bool isPending(String entryId) =>
      statusOf(entryId) == TranslationStatus.pending;

  static bool hasTranslation(String entryId) =>
      statusOf(entryId) == TranslationStatus.done;

  static int countByStatus(TranslationStatus status) {
    ensureHydrated();
    recordsVersion.value;
    return _records.values.where((record) => record.status == status).length;
  }

  static Map<String, TranslationRecord> recordsByStatus(
    TranslationStatus status,
  ) {
    ensureHydrated();
    recordsVersion.value;
    return Map.unmodifiable(
      Map.fromEntries(
        _records.entries.where((entry) => entry.value.status == status),
      ),
    );
  }

  /// 标记为 pending（自动翻译入队时用，让卡片立即显示翻译中）
  static void markPending(String entryId) {
    ensureHydrated();
    if (_records.containsKey(entryId) && _records[entryId]!.isTranslated) {
      return; // 已翻译的不覆盖
    }
    _records[entryId] = TranslationRecord(
      status: TranslationStatus.pending,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _notifyRecordChanged(entryId);
    // pending 不落盘 — 瞬态，重启后无需恢复
  }

  static String displayTitleFor(ArticleModel article) {
    final record = recordOf(article.entryId);
    final translated = record?.translatedTitle?.trim();
    if (translated != null && translated.isNotEmpty) {
      return translated;
    }
    return article.title;
  }

  static String? translatedContentFor(String entryId) {
    final record = recordOf(entryId);
    return record?.translatedContent;
  }

  static Future<TranslationRecord> translateArticle(
    ArticleModel article, {
    String targetLang = '简体中文',
    String? overrideContent,
    bool automatic = false,
  }) {
    ensureHydrated();
    final existing = _inFlight[article.entryId];
    if (existing != null) return existing;

    final accountRevision = AccountSessionGuard.revision;
    final future = _translateArticleInternal(
      article,
      targetLang,
      overrideContent,
      accountRevision,
      automatic,
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

  static Future<TranslationRecord> _translateArticleInternal(
    ArticleModel article,
    String targetLang,
    String? overrideContent,
    int accountRevision,
    bool automatic,
  ) async {
    if (!automatic) {
      await LlmAutoRetryBlockService.clear(
        LlmTaskType.translation,
        article.entryId,
      );
    }
    final apiKey = getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError('DeepSeek API key not configured');
    }

    final previous = recordOf(article.entryId);
    // pending 只写内存，不落盘
    _records[article.entryId] =
        (previous ??
                TranslationRecord(
                  status: TranslationStatus.idle,
                  updatedAt: DateTime.now().millisecondsSinceEpoch,
                ))
            .copyWith(
              status: TranslationStatus.pending,
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
    // 正文过大时分块翻译，避免 LLM 输出畸形 JSON
    const chunkThreshold = 35 * 1024;
    if (htmlContent.length > chunkThreshold) {
      return _translateInChunks(
        article,
        targetLang,
        htmlContent,
        previous,
        accountRevision,
      );
    }
    if (htmlContent.isEmpty) {
      final record = TranslationRecord(
        status: TranslationStatus.error,
        errorMessage: '文章内容为空，无法翻译',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _writeRecord(
        article.entryId,
        record,
        accountRevision: accountRevision,
      );
      return record;
    }

    final systemPrompt = getPrompt(targetLang);
    final userContent =
        'JSON 结构必须是：{"translated_title":"...","translated_html":"..."}\n\n'
        '标题：\n${article.title}\n\nHTML：\n<html>$htmlContent</html>';

    final maxRetries =
        GStorage.setting.get('auto_retry_max_count', defaultValue: 3) as int;
    final totalAttempts = maxRetries > 0 ? maxRetries + 1 : 1;

    for (int attempt = 1; attempt <= totalAttempts; attempt++) {
      final llmConfig = LlmConfig.loadTranslate();
      final trace = LlmRequestTrace(
        task: LlmTaskType.translation,
        config: llmConfig,
        prompt: systemPrompt,
        articleId: article.entryId,
        attempt: attempt,
      );
      try {
        final requestBody = <String, dynamic>{
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': userContent},
          ],
          'response_format': {'type': 'json_object'},
          'stream': false,
          ...llmConfig.toRequestBody(),
        };

        final response = await _dio.post(
          '/chat/completions',
          data: requestBody,
          options: Options(
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
          ),
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
          throw StateError('DeepSeek returned an empty translation result');
        }

        final parsed = _decodeJsonObject(content);
        final translatedTitle = HtmlEntityUtils.decodeText(
          (parsed['translated_title'] ?? parsed['title'] ?? '')
              .toString()
              .trim(),
        );
        final translatedHtml =
            (parsed['translated_html'] ?? parsed['content'] ?? '')
                .toString()
                .trim();

        if (translatedHtml.isEmpty) {
          throw StateError(
            'DeepSeek translation result missing translated_html',
          );
        }

        final record = TranslationRecord(
          status: TranslationStatus.done,
          translatedTitle: translatedTitle.isEmpty ? null : translatedTitle,
          translatedContent: _cleanTranslatedContent(translatedHtml),
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
        await _writeRecord(
          article.entryId,
          record,
          accountRevision: accountRevision,
        );
        await trace.complete();
        return record;
      } catch (e) {
        await trace.fail(e);
        if (e is _StaleAccountOperation ||
            !AccountSessionGuard.isCurrent(accountRevision)) {
          rethrow;
        }
        final failure = LlmFailurePolicy.classify(e);
        if (failure != null) {
          await LlmAutoRetryBlockService.block(
            LlmTaskType.translation,
            article.entryId,
            failure,
          );
        }
        if (failure == null && attempt < totalAttempts) {
          debugPrint(
            '[Translation] Attempt $attempt failed for ${article.entryId}, retrying in 1s...',
          );
          await _waitBeforeRetry();
          continue;
        }

        final errorMessage = LlmFailurePolicy.displayMessage(e);

        await _restoreAfterFailure(
          article.entryId,
          previous,
          errorMessage,
          accountRevision,
          terminal: failure != null,
        );
        return TranslationRecord(
          status: TranslationStatus.error,
          errorMessage: errorMessage,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
      }
    }

    return TranslationRecord(
      status: TranslationStatus.error,
      errorMessage: '重试次数已用尽',
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  // ─── 分块翻译 ──────────────────────────────────

  static const int _chunkSize = 12 * 1024; // 每块 ≤12KB

  /// 分块翻译大文章：按段落边界切成小块，并行请求 LLM，拼接结果
  static Future<TranslationRecord> _translateInChunks(
    ArticleModel article,
    String targetLang,
    String htmlContent,
    TranslationRecord? previous,
    int accountRevision,
  ) async {
    final apiKey = getApiKey()!;
    final chunks = _splitHtmlIntoChunks(htmlContent);
    final maxRetries =
        GStorage.setting.get('auto_retry_max_count', defaultValue: 3) as int;
    final totalAttempts = maxRetries > 0 ? maxRetries + 1 : 1;
    debugPrint('[Translation] 🧩 ${article.entryId}: 切分为 ${chunks.length} 块');

    final llmConfig = LlmConfig.loadTranslate();
    final result = await _translateChunkBatch(
      article: article,
      targetLang: targetLang,
      chunks: chunks,
      apiKey: apiKey,
      llmConfig: llmConfig,
      totalAttempts: totalAttempts,
      accountRevision: accountRevision,
    );
    if (!AccountSessionGuard.isCurrent(accountRevision)) {
      throw const _StaleAccountOperation();
    }
    if (result.record != null) {
      await _writeRecord(
        article.entryId,
        result.record!,
        accountRevision: accountRevision,
      );
      return result.record!;
    }

    final failure = result.failureCause == null
        ? null
        : LlmFailurePolicy.classify(result.failureCause!);
    if (failure != null) {
      await LlmAutoRetryBlockService.block(
        LlmTaskType.translation,
        article.entryId,
        failure,
      );
    }

    final errorMessage =
        failure?.userMessage ??
        (result.failureSummary == null
            ? '分块翻译失败，已重试${totalAttempts - 1}次'
            : '分块翻译失败，已重试${totalAttempts - 1}次；最后一次失败：${result.failureSummary}');
    await _restoreAfterFailure(
      article.entryId,
      previous,
      errorMessage,
      accountRevision,
      terminal: failure != null,
    );
    return TranslationRecord(
      status: TranslationStatus.error,
      errorMessage: errorMessage,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<_ChunkBatchResult> _translateChunkBatch({
    required ArticleModel article,
    required String targetLang,
    required List<String> chunks,
    required String apiKey,
    required LlmConfig llmConfig,
    required int totalAttempts,
    required int accountRevision,
  }) async {
    final results = <_ChunkResult>[];
    for (var i = 0; i < chunks.length; i++) {
      _ChunkResult? lastFailure;
      for (var attempt = 1; attempt <= totalAttempts; attempt++) {
        final result = await _translateOneChunk(
          i: i,
          total: chunks.length,
          chunkHtml: chunks[i],
          articleId: article.entryId,
          articleTitle: article.title,
          apiKey: apiKey,
          targetLang: targetLang,
          llmConfig: llmConfig,
          attempt: attempt,
        );
        if (!AccountSessionGuard.isCurrent(accountRevision)) {
          throw const _StaleAccountOperation();
        }
        if (result.error == null) {
          results.add(result);
          lastFailure = null;
          break;
        }

        lastFailure = result;
        debugPrint(
          '[Translation] 🧩 第 ${i + 1}/${chunks.length} 块'
          '第 $attempt 次失败：${result.error}',
        );
        if (result.failureCause != null &&
            LlmFailurePolicy.classify(result.failureCause!) != null) {
          break;
        }
        if (attempt < totalAttempts) {
          await _waitBeforeRetry();
        }
      }
      if (lastFailure != null) {
        return _ChunkBatchResult.failure(
          _formatChunkFailures([lastFailure], chunks.length),
          failureCause: lastFailure.failureCause,
        );
      }
    }

    final parts = <String>[];
    final titleParts = <String>[];
    for (final r in results) {
      parts.add(r.html!);
      if (r.title != null) titleParts.add(r.title!);
    }

    final translatedTitle = titleParts.isEmpty
        ? null
        : titleParts.join(' ').trim();
    return _ChunkBatchResult.success(
      TranslationRecord(
        status: TranslationStatus.done,
        translatedTitle: (translatedTitle?.isNotEmpty == true)
            ? translatedTitle
            : null,
        translatedContent: _cleanTranslatedContent(parts.join('')),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  static Future<_ChunkResult> _translateOneChunk({
    required int i,
    required int total,
    required String chunkHtml,
    required String articleId,
    required String articleTitle,
    required String apiKey,
    required String targetLang,
    required LlmConfig llmConfig,
    required int attempt,
  }) async {
    final isFirst = i == 0;
    final systemPrompt = getPrompt(targetLang);
    final userContent = isFirst
        ? '这是文章的第 1/$total 段。\n'
              'JSON 结构必须是：{"translated_title":"...","translated_html":"..."}\n\n'
              '标题：\n$articleTitle\n\nHTML：\n<html>$chunkHtml</html>'
        : '这是文章的第 ${i + 1}/$total 段。\n'
              'JSON 结构必须是：{"translated_html":"..."}，不要返回标题。\n\n'
              'HTML：\n<html>$chunkHtml</html>';

    final trace = LlmRequestTrace(
      task: LlmTaskType.translation,
      config: llmConfig,
      prompt: systemPrompt,
      articleId: articleId,
      chunkIndex: i,
      chunkCount: total,
      attempt: attempt,
    );

    try {
      // 每个并发请求用独立 header，避免共享 Dio 实例的状态竞争
      final options = Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
      );
      final response = await _dio.post(
        '/chat/completions',
        data: {
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': userContent},
          ],
          'response_format': {'type': 'json_object'},
          'stream': false,
          ...llmConfig.toRequestBody(),
        },
        options: options,
      );
      await trace.recordResponse(
        response.data,
        httpStatus: response.statusCode,
      );

      final content = _extractMessageContent(response.data);
      if (content == null || content.trim().isEmpty) {
        throw StateError('空响应');
      }

      Map<String, dynamic> parsed;
      try {
        parsed = _decodeJsonObject(content);
      } on FormatException catch (e) {
        final finishReason = _extractFinishReason(response.data);
        final reason = finishReason == 'length'
            ? '响应被截断'
            : 'JSON 解析失败：${_compactFormatException(e)}';
        throw FormatException(reason);
      }

      final title = isFirst
          ? HtmlEntityUtils.decodeText(
              (parsed['translated_title'] ?? '').toString().trim(),
            )
          : null;
      final html = (parsed['translated_html'] ?? '').toString().trim();
      if (html.isEmpty) {
        throw StateError('缺少 translated_html');
      }
      final result = _ChunkResult(
        i,
        title: (title?.isNotEmpty == true) ? title : null,
        html: html,
      );
      await trace.complete();
      return result;
    } catch (e) {
      await trace.fail(e);
      return _ChunkResult(i, error: e.toString(), failureCause: e);
    }
  }

  /// 按段落边界切割 HTML，每块 ≤ _chunkSize
  static List<String> _splitHtmlIntoChunks(String html) {
    final chunks = <String>[];
    final buf = StringBuffer();
    var i = 0;

    while (i < html.length) {
      // 找下一个段落起始标签 <p>, <h1>-<h6>, <li>, <blockquote>, <div
      final nextBlock = _findNextBlockTag(html, i + 1);
      final segmentEnd = nextBlock > i ? nextBlock : html.length;
      final segment = html.substring(i, segmentEnd);

      if (buf.length + segment.length > _chunkSize && buf.isNotEmpty) {
        chunks.add(buf.toString());
        buf.clear();
      }
      buf.write(segment);
      i = segmentEnd;
    }

    if (buf.isNotEmpty) chunks.add(buf.toString());
    return chunks;
  }

  static final _blockTagRe = RegExp(
    r'<(p|h[1-6]|li|blockquote|div|ul|ol|table)\b[^>]*>',
  );

  static int _findNextBlockTag(String html, int from) {
    // 匹配 from 之后下一个块级标签的起始位置
    final idx = html.indexOf(_blockTagRe, from);
    return idx;
  }

  // ─── JSON 解析辅助 ───────────────────────────

  static Future<void> deleteTranslation(String entryId) async {
    ensureHydrated();
    _records.remove(entryId);
    await GStorage.translations.delete(entryId);
    _notifyRecordChanged(entryId);
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

  static Future<void> _restoreAfterFailure(
    String entryId,
    TranslationRecord? previous,
    String errorMessage,
    int accountRevision, {
    bool terminal = false,
  }) async {
    if (previous != null) {
      await _writeRecord(
        entryId,
        previous.copyWith(
          status: previous.isTranslated
              ? TranslationStatus.done
              : terminal
              ? TranslationStatus.error
              : TranslationStatus.idle,
          errorMessage: errorMessage,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
        accountRevision: accountRevision,
      );
    } else {
      final record = TranslationRecord(
        status: TranslationStatus.error,
        errorMessage: errorMessage,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _writeRecord(entryId, record, accountRevision: accountRevision);
    }
  }

  /// 完成态与错误态必须等待持久化成功后再对外报告，避免完成后立即
  /// 退出应用丢失翻译结果；pending 仍只存在于内存中，不落盘。
  static Future<void> _writeRecord(
    String entryId,
    TranslationRecord record, {
    int? accountRevision,
  }) async {
    if (accountRevision != null &&
        !AccountSessionGuard.isCurrent(accountRevision)) {
      return;
    }
    ensureHydrated();
    _records[entryId] = record;
    await GStorage.translations.put(entryId, record.toJson());
    _notifyRecordChanged(entryId);
  }

  static String _cleanTranslatedContent(String raw) {
    var content = raw.trim();
    if (content.startsWith('```')) {
      content = content.replaceFirst(RegExp(r'^```[a-zA-Z0-9]*\s*'), '');
      content = content.replaceFirst(RegExp(r'\s*```$'), '');
    }
    if (content.startsWith('<html>') && content.endsWith('</html>')) {
      content = content.substring(6, content.length - 7).trim();
    }
    return content;
  }

  static String _normalizeJsonPayload(String raw) {
    var content = raw.trim();
    // 去掉 markdown 代码块包裹
    if (content.startsWith('```')) {
      content = content.replaceFirst(RegExp(r'^```[a-zA-Z0-9]*\s*'), '');
      content = content.replaceFirst(RegExp(r'\s*```$'), '');
    }
    // 去掉首尾非 JSON 文本（模型有时在 JSON 前后附加说明文字）
    final firstBrace = content.indexOf('{');
    final lastBrace = content.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      content = content.substring(firstBrace, lastBrace + 1);
    }
    return content;
  }

  static Map<String, dynamic> _decodeJsonObject(String raw) {
    final normalized = _normalizeJsonPayload(raw);
    try {
      return jsonDecode(normalized) as Map<String, dynamic>;
    } on FormatException {
      // Some DeepSeek JSON-mode responses contain literal line breaks inside
      // translated_html or invalid escapes such as `\%`. Repair only those
      // string-level violations; incomplete objects remain invalid.
      return jsonDecode(_repairJsonStringCharacters(normalized))
          as Map<String, dynamic>;
    }
  }

  static String _repairJsonStringCharacters(String raw) {
    final repaired = StringBuffer();
    var inString = false;
    for (var i = 0; i < raw.length; i++) {
      final codeUnit = raw.codeUnitAt(i);
      final char = raw[i];
      if (!inString) {
        repaired.write(char);
        if (char == '"') inString = true;
        continue;
      }

      if (char == '"') {
        repaired.write(char);
        inString = false;
        continue;
      }
      if (char == '\\') {
        final next = i + 1 < raw.length ? raw[i + 1] : null;
        if (next != null && '"\\/bfnrtu'.contains(next)) {
          repaired.write(char);
          repaired.write(next);
          i++;
        } else {
          repaired.write(r'\\');
        }
        continue;
      }
      switch (codeUnit) {
        case 0x08:
          repaired.write(r'\b');
          continue;
        case 0x09:
          repaired.write(r'\t');
          continue;
        case 0x0A:
          repaired.write(r'\n');
          continue;
        case 0x0C:
          repaired.write(r'\f');
          continue;
        case 0x0D:
          repaired.write(r'\r');
          continue;
        default:
          if (codeUnit < 0x20) {
            repaired.write('\\u${codeUnit.toRadixString(16).padLeft(4, '0')}');
          } else {
            repaired.write(char);
          }
      }
    }
    return repaired.toString();
  }

  static String _compactFormatException(FormatException e) {
    final message = e.message.trim();
    if (message.isEmpty) return '格式不合法';
    return message.length <= 80 ? message : '${message.substring(0, 80)}...';
  }

  static Future<void> _waitBeforeRetry() {
    final override = debugRetryDelayOverride;
    if (override != null) return override(const Duration(seconds: 1));
    return Future.delayed(const Duration(seconds: 1));
  }

  static String _formatChunkFailures(List<_ChunkResult> failed, int total) {
    return failed
        .take(3)
        .map((r) => '第 ${r.index + 1}/$total 块 ${r.error ?? '失败'}')
        .join('；');
  }

  static String? _extractMessageContent(dynamic data) {
    final choices = data is Map<String, dynamic> ? data['choices'] : null;
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map<String, dynamic>) {
        final message = first['message'];
        if (message is Map<String, dynamic>) {
          final content = message['content'];
          if (content is String) {
            return content;
          }
        }
      }
    }
    return null;
  }

  static String? _extractFinishReason(dynamic data) {
    final choices = data is Map<String, dynamic> ? data['choices'] : null;
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map<String, dynamic>) {
        final reason = first['finish_reason'];
        if (reason is String) return reason;
      }
    }
    return null;
  }
}

class _StaleAccountOperation implements Exception {
  const _StaleAccountOperation();
}

// ─── 分块翻译结果 ─────────────────────────────

final class _ChunkBatchResult {
  final TranslationRecord? record;
  final String? failureSummary;
  final Object? failureCause;

  const _ChunkBatchResult._({
    this.record,
    this.failureSummary,
    this.failureCause,
  });

  factory _ChunkBatchResult.success(TranslationRecord record) {
    return _ChunkBatchResult._(record: record);
  }

  factory _ChunkBatchResult.failure(
    String failureSummary, {
    Object? failureCause,
  }) {
    return _ChunkBatchResult._(
      failureSummary: failureSummary,
      failureCause: failureCause,
    );
  }
}

final class _ChunkResult {
  final int index;
  final String? title;
  final String? html;
  final String? error;
  final Object? failureCause;
  _ChunkResult(
    this.index, {
    this.title,
    this.html,
    this.error,
    this.failureCause,
  });
}
