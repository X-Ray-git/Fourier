import 'dart:convert';
import 'package:dio/dio.dart';

import '../models/article.dart';
import '../utils/article_content_utils.dart';
import '../utils/storage.dart';
import 'llm_config.dart';
import 'llm_usage_ledger.dart';

/// AI 文章过滤结果
class FilterResult {
  final bool shouldReject;
  final String reason;

  const FilterResult({required this.shouldReject, required this.reason});
}

/// AI 文章过滤服务 — 使用 DeepSeek JSON Output 判定是否过滤
abstract final class ArticleFilterService {
  static const String _apiBase = 'https://api.deepseek.com';
  static const Duration _timeout = Duration(seconds: 120);

  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _apiBase,
      connectTimeout: _timeout,
      receiveTimeout: _timeout,
      sendTimeout: _timeout,
    ),
  );

  static String getApiKey() {
    return GStorage.setting.get('deepseek_api_key', defaultValue: '') as String;
  }

  static void setApiKey(String key) {
    GStorage.setting.put('deepseek_api_key', key);
  }

  /// 获取当前 prompt。已保存或导入的值始终优先于代码默认值。
  static String getPrompt() {
    return GStorage.setting.get('filter_prompt', defaultValue: _defaultPrompt)
        as String;
  }

  static Future<void> setPrompt(String prompt) async {
    await GStorage.setting.put('filter_prompt', prompt);
  }

  static void resetPrompt() {
    GStorage.setting.delete('filter_prompt');
  }

  /// 判定单篇文章
  static Future<FilterResult> filterArticle(ArticleModel article) async {
    final apiKey = getApiKey();
    if (apiKey.isEmpty) {
      throw StateError('DeepSeek API key not configured');
    }

    final htmlContent = ArticleContentUtils.normalizeHtml(
      article.content ?? '',
      sourceUrl: article.url,
    );
    final textContent = htmlContent
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final prompt = getPrompt();
    final title = article.title;
    final source = article.feedTitle;
    final channelHint = article.feedId.isNotEmpty
        ? '来源频道ID: ${article.feedId}'
        : '';

    _dio.options.headers['Authorization'] = 'Bearer $apiKey';
    _dio.options.headers['Content-Type'] = 'application/json';

    final config = LlmConfig.loadFilter();
    final requestBody = <String, dynamic>{
      'messages': [
        {'role': 'system', 'content': prompt},
        {
          'role': 'user',
          'content':
              '频道: $source\n$channelHint\n标题: $title\n正文前500字: ${textContent.substring(0, textContent.length.clamp(0, 500))}',
        },
      ],
      'response_format': {'type': 'json_object'},
      'stream': false,
      ...config.toRequestBody(),
    };
    final trace = LlmRequestTrace(
      task: LlmTaskType.filter,
      config: config,
      prompt: prompt,
      articleId: article.entryId,
    );
    try {
      final response = await _dio.post('/chat/completions', data: requestBody);
      await trace.recordResponse(
        response.data,
        httpStatus: response.statusCode,
      );

      final data = response.data as Map<String, dynamic>?;
      final choices = data?['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) {
        throw StateError('DeepSeek returned empty response');
      }
      final message = (choices.first as Map<String, dynamic>)['message'];
      if (message == null) {
        throw StateError('DeepSeek response missing message');
      }
      final content = message['content'] as String?;
      if (content == null || content.trim().isEmpty) {
        throw StateError('DeepSeek returned empty filter result');
      }

      var raw = content.trim();
      if (raw.startsWith('```')) {
        raw = raw.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
        raw = raw.replaceFirst(RegExp(r'\s*```$'), '');
      }
      final first = raw.indexOf('{');
      final last = raw.lastIndexOf('}');
      if (first >= 0 && last > first) {
        raw = raw.substring(first, last + 1);
      }

      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      final result = FilterResult(
        shouldReject: parsed['should_reject'] == true,
        reason: (parsed['reason'] ?? '未分类').toString(),
      );
      await trace.complete();
      return result;
    } catch (error) {
      await trace.fail(error);
      rethrow;
    }
  }

  // ─── 默认 Prompt ─────────────────────────────────────────────

  static const String _defaultPrompt = '''
你是一个通用的文章质量审核助手。请判断给定内容是否明显属于不适合进入阅读列表的低质量噪声，并返回 JSON。

主题、领域、观点立场和文章来源本身都不是过滤依据。只在有明确证据时过滤：
1. 正文为空，或只剩导航、登录提示、Cookie 提示、错误页面等网页模板内容。
2. 内容因抓取或编码错误而严重残缺、重复、乱码，已经无法正常阅读。
3. 纯广告、联盟推广、诱导点击或垃圾信息，且没有独立、实质性的可读内容。
4. 标题与正文明显无关，正文也没有提供标题所承诺的有效信息。

以下情况应当保留：
- 正常的新闻、观点、教程、研究、产品公告或商业信息，不论主题是否小众。
- 有营销色彩但仍包含实质信息的文章。
- 信息较短但内容完整的文章。
- 无法确定是否属于低质量噪声的文章；不确定时优先保留。

reason 应简短说明实际观察到的问题，不要猜测作者动机，也不要使用个性化兴趣作为理由。

返回 JSON（直接输出，不要 Markdown 标记）：
{"should_reject": true或false, "reason": "命中原因的简短中文"}
''';
}
