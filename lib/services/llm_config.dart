import '../utils/storage.dart';

/// LLM 参数配置（翻译 / 摘要各自独立）
class LlmConfig {
  static const int minConcurrency = 1;
  static const int maxConcurrency = 1024;
  static const String flashModel = 'deepseek-flash';
  static const List<String> supportedModels = [flashModel, 'deepseek-v4-pro'];
  static const List<String> supportedVisionModels = [flashModel];
  static const String defaultVisionModel = flashModel;
  static const String summaryVisionModelKey = 'llm_summary_vision_model';
  static const String filterVisionModelKey = 'llm_filter_vision_model';

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
    model: flashModel,
    thinking: false,
    reasoningEffort: 'high',
    temperature: 0.2,
    maxTokens: 131072,
    concurrency: 32,
  );

  static const LlmConfig summaryDefault = LlmConfig(
    model: flashModel,
    thinking: true,
    reasoningEffort: 'max',
    temperature: 0.2,
    maxTokens: 2048,
    concurrency: 32,
  );

  static const LlmConfig filterDefault = LlmConfig(
    model: flashModel,
    thinking: true,
    reasoningEffort: 'max',
    temperature: 0.1,
    maxTokens: 2048,
    concurrency: 32,
  );

  static const LlmConfig relationDefault = LlmConfig(
    model: flashModel,
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

  static String loadSummaryVisionModel() =>
      _loadVisionModel(summaryVisionModelKey);
  static String loadFilterVisionModel() =>
      _loadVisionModel(filterVisionModelKey);

  static Future<void> saveSummaryVisionModel(String model) =>
      _saveVisionModel(summaryVisionModelKey, model);
  static Future<void> saveFilterVisionModel(String model) =>
      _saveVisionModel(filterVisionModelKey, model);

  static bool isVisionModelSettingKey(String key) =>
      key == summaryVisionModelKey || key == filterVisionModelKey;

  static bool isSupportedVisionModel(String model) =>
      supportedVisionModels.contains(canonicalModelName(model));

  /// DeepSeek temporarily accepts these retired aliases, but new requests and
  /// exported settings should use the canonical V4.1 Flash model name.
  static String canonicalModelName(String model) {
    switch (model) {
      case 'deepseek-v4-flash':
      case 'deepseek-v4-flash-vision-exp':
        return flashModel;
      default:
        return model;
    }
  }

  static Future<void> migrateLegacyModelAliases() async {
    const keys = [
      '${_translatePrefix}model',
      '${_summaryPrefix}model',
      '${_filterPrefix}model',
      '${_relationPrefix}model',
      summaryVisionModelKey,
      filterVisionModelKey,
    ];
    final updates = <String, String>{};
    for (final key in keys) {
      final stored = GStorage.setting.get(key);
      if (stored is! String) continue;
      final canonical = canonicalModelName(stored);
      if (canonical != stored) updates[key] = canonical;
    }
    if (updates.isNotEmpty) await GStorage.setting.putAll(updates);
  }

  // ─── 构建 API 请求体 ───

  Map<String, dynamic> toRequestBody() {
    final body = <String, dynamic>{
      'model': model,
      'temperature': temperature,
      'max_tokens': maxTokens,
      // DeepSeek defaults to thinking mode when this field is omitted. Send
      // the explicit disabled state so the user's false setting reaches the
      // provider instead of being interpreted as the provider default.
      'thinking': {'type': thinking ? 'enabled' : 'disabled'},
    };
    if (thinking) {
      body['reasoning_effort'] = reasoningEffort;
    }
    return body;
  }

  // ─── 内部 ───

  static LlmConfig _load(String prefix, LlmConfig defaults) {
    return LlmConfig(
      model: canonicalModelName(
        (GStorage.setting.get('${prefix}model') as String?) ?? defaults.model,
      ),
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
      '${prefix}model': canonicalModelName(c.model),
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
      '${prefix}vision_model',
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

  static String _loadVisionModel(String key) {
    final stored = GStorage.setting.get(key);
    final canonical = stored is String ? canonicalModelName(stored) : null;
    return canonical != null && isSupportedVisionModel(canonical)
        ? canonical
        : defaultVisionModel;
  }

  static Future<void> _saveVisionModel(String key, String model) async {
    final canonical = canonicalModelName(model);
    if (!isSupportedVisionModel(canonical)) {
      throw ArgumentError.value(model, 'model', '不支持的视觉模型');
    }
    await GStorage.setting.put(key, canonical);
  }
}
