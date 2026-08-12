import 'dart:convert';

import 'package:flutter/services.dart';

import '../common/constants/constants.dart';
import '../utils/storage.dart';
import 'article_relation_prompt_service.dart';
import 'article_relation_service.dart';
import 'article_relation_worker.dart';
import 'feed_readability_settings_service.dart';
import 'feed_silent_settings_service.dart';
import 'feed_translation_settings_service.dart';
import 'summary_service.dart';
import 'translation_service.dart';

class SettingsBackupSummary {
  final int settingCount;
  final int feedPreferenceCount;
  final bool hasFoloCredentials;
  final bool hasDeepseekApiKey;

  const SettingsBackupSummary({
    required this.settingCount,
    required this.feedPreferenceCount,
    required this.hasFoloCredentials,
    required this.hasDeepseekApiKey,
  });

  bool get containsSensitiveData => hasFoloCredentials || hasDeepseekApiKey;
}

class SettingsBackupPayload {
  const SettingsBackupPayload({required this.settings, required this.summary});

  final Map<String, dynamic> settings;
  final SettingsBackupSummary summary;

  String? get sessionToken => settings[StorageKeys.sessionToken] as String?;
}

abstract final class SettingsBackupService {
  static const String backupType = 'fourier_settings';
  // Existing Auto Folo exports are the supported migration path after the
  // application identifiers change to Fourier.
  static const Set<String> _supportedBackupTypes = {
    backupType,
    'auto_folo_settings',
  };
  static const int currentVersion = 1;

  static const _deepseekApiKey = 'deepseek_api_key';
  static const _autoRetryMaxCount = 'auto_retry_max_count';
  static const _translationPrompt = 'translation_prompt';
  static const _summaryPrompt = 'summary_prompt';
  static const _filterPrompt = 'filter_prompt';
  static const _relationPrompt = 'relation_prompt';

  static const _llmPrefixes = [
    'llm_translate_',
    'llm_summary_',
    'llm_filter_',
    'llm_relation_',
  ];
  static const _feedPreferencePrefixes = [
    'feed_auto_translate_',
    'feed_silent_',
    'feed_auto_readability_',
  ];

  static const _fixedKeys = {
    StorageKeys.sessionToken,
    StorageKeys.readSyncWindowDays,
    StorageKeys.appearanceMode,
    StorageKeys.badgeStrategy,
    StorageKeys.articleContentMaxWidth,
    StorageKeys.macosMaxFlingVelocity,
    StorageKeys.articleRelationEnabled,
    _deepseekApiKey,
    _autoRetryMaxCount,
    _translationPrompt,
    _summaryPrompt,
    _filterPrompt,
    _relationPrompt,
  };

  static const _stringKeys = {
    StorageKeys.sessionToken,
    StorageKeys.appearanceMode,
    StorageKeys.badgeStrategy,
    _deepseekApiKey,
    _translationPrompt,
    _summaryPrompt,
    _filterPrompt,
    _relationPrompt,
  };

  static const _intKeys = {
    StorageKeys.readSyncWindowDays,
    StorageKeys.articleContentMaxWidth,
    StorageKeys.macosMaxFlingVelocity,
    _autoRetryMaxCount,
  };

  static const _boolKeys = {StorageKeys.articleRelationEnabled};

  static Future<SettingsBackupSummary> exportToClipboard() async {
    final settings = exportSettings();
    final payload = {
      'type': backupType,
      'version': currentVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'settings': settings,
    };
    const encoder = JsonEncoder.withIndent('  ');
    await Clipboard.setData(ClipboardData(text: encoder.convert(payload)));
    return summarize(settings);
  }

  static Map<String, dynamic> exportSettings() {
    final settings = <String, dynamic>{};
    for (final rawKey in GStorage.setting.keys) {
      if (rawKey is! String || !_isManagedKey(rawKey)) continue;
      final value = GStorage.setting.get(rawKey);
      if (_isJsonPrimitive(value)) {
        settings[rawKey] = value;
      }
    }
    return settings;
  }

  static Future<SettingsBackupSummary> importFromClipboard() async {
    final payload = await readFromClipboard();
    await applyPayload(payload);
    return payload.summary;
  }

  static Future<SettingsBackupPayload> readFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      throw const FormatException('剪贴板没有可导入的配置 JSON');
    }
    return parseJson(text);
  }

  static Future<SettingsBackupSummary> importFromJson(String text) async {
    final payload = parseJson(text);
    await applyPayload(payload);
    return payload.summary;
  }

  static SettingsBackupPayload parseJson(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException('配置 JSON 顶层必须是对象');
    }

    if (!_supportedBackupTypes.contains(decoded['type'])) {
      throw const FormatException('不是 Fourier 设置备份');
    }

    final version = decoded['version'];
    if (version is! int || version < 1 || version > currentVersion) {
      throw FormatException('不支持的配置版本：$version');
    }

    final rawSettings = decoded['settings'];
    if (rawSettings is! Map) {
      throw const FormatException('配置 JSON 缺少 settings 对象');
    }

    final settings = <String, dynamic>{};
    for (final entry in rawSettings.entries) {
      final key = entry.key;
      if (key is! String || !_isImportableKey(key)) continue;
      if (_isLegacyCredentialKey(key)) continue;
      settings[key] = _normalizeValue(key, entry.value);
    }

    return SettingsBackupPayload(
      settings: settings,
      summary: summarize(settings),
    );
  }

  static Future<void> applyPayload(SettingsBackupPayload payload) async {
    final relationWasEnabled = ArticleRelationService.isEnabled;
    await _replaceManagedSettings(payload.settings);
    await ArticleRelationPromptService.migrateLegacyDefaultPrompt();
    _refreshRuntimeCaches();
    await ArticleRelationWorker.applyStoredEnabledSetting(relationWasEnabled);
  }

  static SettingsBackupSummary summarize(Map<String, dynamic> settings) {
    final feedPreferenceCount = settings.keys
        .where((key) => _startsWithAny(key, _feedPreferencePrefixes))
        .length;
    final hasFoloCredentials =
        (settings[StorageKeys.sessionToken] as String?)?.isNotEmpty == true;
    final hasDeepseekApiKey =
        (settings[_deepseekApiKey] as String?)?.isNotEmpty == true;

    return SettingsBackupSummary(
      settingCount: settings.length,
      feedPreferenceCount: feedPreferenceCount,
      hasFoloCredentials: hasFoloCredentials,
      hasDeepseekApiKey: hasDeepseekApiKey,
    );
  }

  static Future<void> _replaceManagedSettings(
    Map<String, dynamic> settings,
  ) async {
    final keysToDelete = <String>[];
    for (final key in GStorage.setting.keys) {
      if (key is String &&
          (_isManagedKey(key) || _isLegacyCredentialKey(key))) {
        keysToDelete.add(key);
      }
    }

    for (final key in keysToDelete) {
      await GStorage.setting.delete(key);
    }
    await GStorage.setting.putAll(settings);

    if (_changesPrefix(keysToDelete, settings, 'feed_silent_')) {
      FeedSilentSettingsService.version.value++;
    }
    if (_changesPrefix(keysToDelete, settings, 'feed_auto_readability_')) {
      FeedReadabilitySettingsService.version.value++;
    }
    if (_changesPrefix(keysToDelete, settings, 'feed_auto_translate_')) {
      FeedTranslationSettingsService.version.value++;
    }
  }

  static void _refreshRuntimeCaches() {
    final apiKey = GStorage.setting.get(_deepseekApiKey) as String?;
    TranslationService.setApiKey(apiKey ?? '');
    SummaryService.setApiKey(apiKey ?? '');
  }

  static bool _isManagedKey(String key) {
    return _fixedKeys.contains(key) ||
        _startsWithAny(key, _llmPrefixes) ||
        _startsWithAny(key, _feedPreferencePrefixes);
  }

  static bool _isImportableKey(String key) =>
      _isManagedKey(key) || _isLegacyCredentialKey(key);

  static bool _isLegacyCredentialKey(String key) =>
      key == StorageKeys.clientId || key == StorageKeys.sessionId;

  static bool _startsWithAny(String key, List<String> prefixes) {
    return prefixes.any(key.startsWith);
  }

  static bool _changesPrefix(
    List<String> deletedKeys,
    Map<String, dynamic> importedSettings,
    String prefix,
  ) {
    return deletedKeys.any((key) => key.startsWith(prefix)) ||
        importedSettings.keys.any((key) => key.startsWith(prefix));
  }

  static bool _isJsonPrimitive(Object? value) {
    return value == null || value is String || value is num || value is bool;
  }

  static dynamic _normalizeValue(String key, Object? value) {
    if (key == StorageKeys.appearanceMode) {
      if (value == 'system' || value == 'light' || value == 'dark') {
        return value;
      }
      throw FormatException('$key 必须是 system、light 或 dark');
    }

    if (_stringKeys.contains(key) ||
        key.endsWith('model') ||
        key.endsWith('reasoning_effort')) {
      if (value is String) return value;
      throw FormatException('$key 必须是字符串');
    }

    if (_intKeys.contains(key) ||
        key.endsWith('max_tokens') ||
        key.endsWith('concurrency')) {
      if (value is int) return value;
      if (value is num && value == value.roundToDouble()) {
        return value.toInt();
      }
      throw FormatException('$key 必须是整数');
    }

    if (key.endsWith('temperature')) {
      if (value is num) return value.toDouble();
      throw FormatException('$key 必须是数字');
    }

    if (_boolKeys.contains(key) ||
        key.endsWith('thinking') ||
        _startsWithAny(key, _feedPreferencePrefixes)) {
      if (value is bool) return value;
      throw FormatException('$key 必须是布尔值');
    }

    throw FormatException('不支持的配置项：$key');
  }
}
