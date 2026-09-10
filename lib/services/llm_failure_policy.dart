import 'dart:convert';

import 'package:dio/dio.dart';

import '../utils/storage.dart';
import 'llm_usage_ledger.dart';

enum LlmFailureCode { contentRisk }

final class LlmFailureDecision {
  final LlmFailureCode code;
  final String userMessage;

  const LlmFailureDecision({required this.code, required this.userMessage});
}

/// Central policy for provider failures that cannot be fixed by retrying the
/// same request unchanged.
abstract final class LlmFailurePolicy {
  static const String contentRiskMessage = 'DeepSeek 内容安全检查拒绝处理此文章';

  static LlmFailureDecision? classify(Object error) {
    final providerMessage = _providerMessage(error);
    if (providerMessage?.trim().toLowerCase() ==
        'content exists risk'.toLowerCase()) {
      return const LlmFailureDecision(
        code: LlmFailureCode.contentRisk,
        userMessage: contentRiskMessage,
      );
    }
    return null;
  }

  static String displayMessage(Object error) {
    final decision = classify(error);
    if (decision != null) return decision.userMessage;
    if (error is DioException) {
      return error.message ?? 'DeepSeek request failed';
    }
    if (error is FormatException) return error.message;
    if (error is StateError) return error.message;
    return error.toString();
  }

  static String? _providerMessage(Object error) {
    if (error is! DioException) return null;
    dynamic data = error.response?.data;
    if (data is List<int>) {
      try {
        data = utf8.decode(data);
      } catch (_) {
        return null;
      }
    }
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {
        return data;
      }
    }
    if (data is! Map) return null;
    final providerError = data['error'];
    if (providerError is Map) return providerError['message']?.toString();
    return data['message']?.toString();
  }
}

/// Account-scoped suppression for deterministic provider rejections.
///
/// The data lives in localCache, so account replacement clears it together
/// with the rest of the derived account state. Manual actions clear their own
/// entry before making a fresh request.
abstract final class LlmAutoRetryBlockService {
  static const String _storageKey = 'llm_auto_retry_blocks_v1';

  static bool isBlocked(LlmTaskType task, String articleId) {
    if (articleId.isEmpty) return false;
    return _read().containsKey(_entryKey(task, articleId));
  }

  static Future<void> block(
    LlmTaskType task,
    String articleId,
    LlmFailureDecision decision,
  ) async {
    if (articleId.isEmpty) return;
    final blocks = _read();
    blocks[_entryKey(task, articleId)] = <String, dynamic>{
      'reason': decision.code.name,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    await GStorage.localCache.put(_storageKey, blocks);
  }

  static Future<void> clear(LlmTaskType task, String articleId) async {
    if (articleId.isEmpty) return;
    final blocks = _read();
    if (blocks.remove(_entryKey(task, articleId)) == null) return;
    if (blocks.isEmpty) {
      await GStorage.localCache.delete(_storageKey);
    } else {
      await GStorage.localCache.put(_storageKey, blocks);
    }
  }

  static Map<String, dynamic> _read() {
    final raw = GStorage.localCache.get(_storageKey);
    if (raw is! Map) return <String, dynamic>{};
    return Map<String, dynamic>.from(raw);
  }

  static String _entryKey(LlmTaskType task, String articleId) =>
      '${task.name}:$articleId';
}
