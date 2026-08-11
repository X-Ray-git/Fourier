import '../utils/storage.dart';

/// LLM 参数配置（翻译 / 摘要各自独立）
class LlmConfig {
  static const int minConcurrency = 1;
  static const int maxConcurrency = 1024;

  final String model;
  final bool thinking;
  final String reasoningEffort; // high / max
  final double temperature;
  final int maxTokens;
  final int concurrency;

  const LlmConfig({
    required this.model,
    required this.thinking,
    required this.reasoningEffort,
    required this.temperature,
    required this.maxTokens,
    this.concurrency = 32,
  });

  LlmConfig copyWith({
    String? model,
    bool? thinking,
    String? reasoningEffort,
    double? temperature,
    int? maxTokens,
    int? concurrency,
  }) {
    return LlmConfig(
      model: model ?? this.model,
      thinking: thinking ?? this.thinking,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      concurrency: concurrency ?? this.concurrency,
    );
  }

  static const _translatePrefix = 'llm_translate_';
  static const _summaryPrefix = 'llm_summary_';
  static const _relationPrefix = 'llm_relation_';

  // ─── 默认值 ───

  static const LlmConfig translateDefault = LlmConfig(
    model: 'deepseek-v4-flash',
    thinking: false,
    reasoningEffort: 'high',
    temperature: 0.2,
    maxTokens: 131072,
    concurrency: 32,
  );

  static const LlmConfig summaryDefault = LlmConfig(
    model: 'deepseek-v4-flash',
    thinking: true,
    reasoningEffort: 'max',
    temperature: 0.2,
    maxTokens: 2048,
    concurrency: 32,
  );

  static const LlmConfig filterDefault = LlmConfig(
    model: 'deepseek-v4-flash',
    thinking: true,
    reasoningEffort: 'max',
    temperature: 0.1,
    maxTokens: 2048,
    concurrency: 32,
  );

  static const LlmConfig relationDefault = LlmConfig(
    model: 'deepseek-v4-flash',
    thinking: true,
    reasoningEffort: 'max',
    temperature: 0,
    maxTokens: 32768,
    concurrency: 1,
  );

  static const _filterPrefix = 'llm_filter_';

  static LlmConfig loadFilter() => _load(_filterPrefix, filterDefault);
  static Future<void> saveFilter(LlmConfig c) => _save(_filterPrefix, c);
  static Future<void> resetFilter() => _clear(_filterPrefix);
  static LlmConfig loadRelation() =>
      _load(_relationPrefix, relationDefault).copyWith(concurrency: 1);
  static Future<void> saveRelation(LlmConfig c) =>
      _save(_relationPrefix, c.copyWith(concurrency: 1));
  static Future<void> resetRelation() => _clear(_relationPrefix);

  // ─── 读写 ───

  static LlmConfig loadTranslate() => _load(_translatePrefix, translateDefault);
  static LlmConfig loadSummary() => _load(_summaryPrefix, summaryDefault);

  static Future<void> saveTranslate(LlmConfig c) => _save(_translatePrefix, c);
  static Future<void> saveSummary(LlmConfig c) => _save(_summaryPrefix, c);

  static Future<void> resetTranslate() => _clear(_translatePrefix);
  static Future<void> resetSummary() => _clear(_summaryPrefix);

  // ─── 构建 API 请求体 ───

  Map<String, dynamic> toRequestBody() {
    final body = <String, dynamic>{
      'model': model,
      'temperature': temperature,
      'max_tokens': maxTokens,
    };
    if (thinking) {
      body['thinking'] = {'type': 'enabled'};
      body['reasoning_effort'] = reasoningEffort;
    }
    return body;
  }

  // ─── 内部 ───

  static LlmConfig _load(String prefix, LlmConfig defaults) {
    return LlmConfig(
      model:
          (GStorage.setting.get('${prefix}model') as String?) ?? defaults.model,
      thinking:
          (GStorage.setting.get('${prefix}thinking') as bool?) ??
          defaults.thinking,
      reasoningEffort:
          (GStorage.setting.get('${prefix}reasoning_effort') as String?) ??
          defaults.reasoningEffort,
      temperature:
          (GStorage.setting.get('${prefix}temperature') as double?) ??
          defaults.temperature,
      maxTokens:
          (GStorage.setting.get('${prefix}max_tokens') as int?) ??
          defaults.maxTokens,
      concurrency: _normalizeConcurrency(
        GStorage.setting.get('${prefix}concurrency'),
        defaults.concurrency,
      ),
    );
  }

  static Future<void> _save(String prefix, LlmConfig c) async {
    await GStorage.setting.putAll({
      '${prefix}model': c.model,
      '${prefix}thinking': c.thinking,
      '${prefix}reasoning_effort': c.reasoningEffort,
      '${prefix}temperature': c.temperature,
      '${prefix}max_tokens': c.maxTokens,
      '${prefix}concurrency': c.concurrency
          .clamp(minConcurrency, maxConcurrency)
          .toInt(),
    });
  }

  static Future<void> _clear(String prefix) async {
    await GStorage.setting.deleteAll([
      '${prefix}model',
      '${prefix}thinking',
      '${prefix}reasoning_effort',
      '${prefix}temperature',
      '${prefix}max_tokens',
      '${prefix}concurrency',
    ]);
  }

  static int _normalizeConcurrency(Object? value, int fallback) {
    if (value is int && value >= minConcurrency && value <= maxConcurrency) {
      return value;
    }
    return fallback;
  }
}
