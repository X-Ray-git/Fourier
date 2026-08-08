import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../utils/storage.dart';
import 'llm_config.dart';

enum LlmTaskType { translation, summary, filter, relation }

class LlmUsageSummary {
  const LlmUsageSummary({
    required this.requestCount,
    required this.successCount,
    required this.failureCount,
    required this.promptTokens,
    required this.cacheHitTokens,
    required this.cacheMissTokens,
    required this.completionTokens,
    required this.reasoningTokens,
    required this.totalTokens,
  });

  final int requestCount;
  final int successCount;
  final int failureCount;
  final int promptTokens;
  final int cacheHitTokens;
  final int cacheMissTokens;
  final int completionTokens;
  final int reasoningTokens;
  final int totalTokens;

  double get cacheHitRate {
    final cacheableTokens = cacheHitTokens + cacheMissTokens;
    return cacheableTokens == 0 ? 0 : cacheHitTokens / cacheableTokens;
  }
}

/// Compact, append-only request telemetry for DeepSeek calls.
///
/// It intentionally excludes prompts, article content, model output and
/// reasoning text. Each HTTP attempt gets its own record so retries and chunked
/// translations remain measurable.
class LlmRequestTrace {
  LlmRequestTrace({
    required this.task,
    required this.config,
    required String prompt,
    this.articleId,
    this.batchId,
    this.chunkIndex,
    this.chunkCount,
    this.attempt = 1,
  }) : promptHash = sha256.convert(utf8.encode(prompt)).toString(),
       startedAt = DateTime.now().millisecondsSinceEpoch,
       id = _nextId();

  static int _counter = 0;

  final String id;
  final LlmTaskType task;
  final LlmConfig config;
  final String promptHash;
  final String? articleId;
  final String? batchId;
  final int? chunkIndex;
  final int? chunkCount;
  final int attempt;
  final int startedAt;

  Map<String, dynamic>? _record;

  static String _nextId() {
    final micros = DateTime.now().microsecondsSinceEpoch;
    return '$micros-${_counter++}';
  }

  Future<void> recordResponse(dynamic rawResponse, {int? httpStatus}) async {
    final completedAt = DateTime.now().millisecondsSinceEpoch;
    final data = rawResponse is Map ? rawResponse : const <String, dynamic>{};
    final choices = data['choices'];
    final choice = choices is List && choices.isNotEmpty && choices.first is Map
        ? choices.first as Map
        : const <String, dynamic>{};
    final usage = data['usage'] is Map
        ? data['usage'] as Map
        : const <String, dynamic>{};
    final completionDetails = usage['completion_tokens_details'] is Map
        ? usage['completion_tokens_details'] as Map
        : const <String, dynamic>{};
    final providerCreatedAt = data['created'] is num
        ? (data['created'] as num).toInt()
        : null;

    int token(String key) => (usage[key] as num?)?.toInt() ?? 0;

    _record = <String, dynamic>{
      'schemaVersion': LlmUsageLedger.schemaVersion,
      'id': id,
      'task': task.name,
      if (articleId != null) 'articleId': articleId,
      if (batchId != null) 'batchId': batchId,
      if (chunkIndex != null) 'chunkIndex': chunkIndex,
      if (chunkCount != null) 'chunkCount': chunkCount,
      'attempt': attempt,
      'startedAt': startedAt,
      'completedAt': completedAt,
      'durationMs': completedAt - startedAt,
      'outcome': 'response_received',
      'httpStatus': ?httpStatus,
      'requestModel': config.model,
      'model': data['model']?.toString() ?? config.model,
      'thinking': config.thinking,
      'reasoningEffort': config.reasoningEffort,
      'temperature': config.temperature,
      'maxTokens': config.maxTokens,
      'promptHash': promptHash,
      if (data['id'] != null) 'providerRequestId': data['id'].toString(),
      'providerCreatedAt': ?providerCreatedAt,
      if (data['system_fingerprint'] != null)
        'systemFingerprint': data['system_fingerprint'].toString(),
      if (choice['finish_reason'] != null)
        'finishReason': choice['finish_reason'].toString(),
      'promptTokens': token('prompt_tokens'),
      'cacheHitTokens': token('prompt_cache_hit_tokens'),
      'cacheMissTokens': token('prompt_cache_miss_tokens'),
      'completionTokens': token('completion_tokens'),
      'reasoningTokens':
          (completionDetails['reasoning_tokens'] as num?)?.toInt() ?? 0,
      'totalTokens': token('total_tokens'),
    };
    await LlmUsageLedger.write(id, _record!);
  }

  Future<void> complete() async {
    await _finish('success');
  }

  Future<void> fail(Object error) async {
    final outcome = _record == null ? 'request_failed' : 'processing_failed';
    await _finish(outcome, error: error);
  }

  Future<void> _finish(String outcome, {Object? error}) async {
    final completedAt = DateTime.now().millisecondsSinceEpoch;
    final record = <String, dynamic>{
      ...?_record,
      'schemaVersion': LlmUsageLedger.schemaVersion,
      'id': id,
      'task': task.name,
      if (articleId != null) 'articleId': articleId,
      if (batchId != null) 'batchId': batchId,
      if (chunkIndex != null) 'chunkIndex': chunkIndex,
      if (chunkCount != null) 'chunkCount': chunkCount,
      'attempt': attempt,
      'startedAt': startedAt,
      'completedAt': completedAt,
      'durationMs': completedAt - startedAt,
      'outcome': outcome,
      'requestModel': config.model,
      'thinking': config.thinking,
      'reasoningEffort': config.reasoningEffort,
      'temperature': config.temperature,
      'maxTokens': config.maxTokens,
      'promptHash': promptHash,
      if (error != null) 'error': _compactError(error),
      if (error is DioException && error.response?.statusCode != null)
        'httpStatus': error.response!.statusCode,
    };
    _record = record;
    await LlmUsageLedger.write(id, record);
  }

  static String _compactError(Object error) {
    final raw = error is DioException
        ? '${error.type.name}: ${error.message ?? 'DeepSeek request failed'}'
        : '${error.runtimeType}: $error';
    return raw.length <= 500 ? raw : raw.substring(0, 500);
  }
}

abstract final class LlmUsageLedger {
  static const int schemaVersion = 1;

  static Future<void> write(String id, Map<String, dynamic> record) async {
    try {
      await GStorage.llmUsageEvents.put(id, record);
    } catch (_) {
      // Telemetry must never change the result of the LLM operation it observes.
    }
  }

  static int get count => GStorage.llmUsageEvents.length;

  static LlmUsageSummary summarize({LlmTaskType? task}) {
    var requestCount = 0;
    var successCount = 0;
    var failureCount = 0;
    var promptTokens = 0;
    var cacheHitTokens = 0;
    var cacheMissTokens = 0;
    var completionTokens = 0;
    var reasoningTokens = 0;
    var totalTokens = 0;

    int value(Map<dynamic, dynamic> record, String key) =>
        (record[key] as num?)?.toInt() ?? 0;

    for (final rawRecord in GStorage.llmUsageEvents.values) {
      if (rawRecord is! Map) continue;
      if (task != null && rawRecord['task'] != task.name) continue;

      requestCount++;
      if (rawRecord['outcome'] == 'success') {
        successCount++;
      } else if (rawRecord['outcome'] == 'request_failed' ||
          rawRecord['outcome'] == 'processing_failed') {
        failureCount++;
      }
      promptTokens += value(rawRecord, 'promptTokens');
      cacheHitTokens += value(rawRecord, 'cacheHitTokens');
      cacheMissTokens += value(rawRecord, 'cacheMissTokens');
      completionTokens += value(rawRecord, 'completionTokens');
      reasoningTokens += value(rawRecord, 'reasoningTokens');
      totalTokens += value(rawRecord, 'totalTokens');
    }

    return LlmUsageSummary(
      requestCount: requestCount,
      successCount: successCount,
      failureCount: failureCount,
      promptTokens: promptTokens,
      cacheHitTokens: cacheHitTokens,
      cacheMissTokens: cacheMissTokens,
      completionTokens: completionTokens,
      reasoningTokens: reasoningTokens,
      totalTokens: totalTokens,
    );
  }
}
