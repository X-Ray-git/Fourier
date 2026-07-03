import 'dart:convert';

import 'package:flutter/services.dart';

import '../common/constants/constants.dart';
import '../utils/storage.dart';
import 'feed_silent_settings_service.dart';
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

abstract final class SettingsBackupService {
  static const String backupType = 'auto_folo_settings';
  static const int currentVersion = 1;

  static const _deepseekApiKey = 'deepseek_api_key';
  static const _autoRetryMaxCount = 'auto_retry_max_count';
  static const _translationPrompt = 'translation_prompt';
  static const _summaryPrompt = 'summary_prompt';
  static const _filterPrompt = 'filter_prompt';

  static const _llmPrefixes = ['llm_translate_', 'llm_summary_', 'llm_filter_'];
  static const _feedPreferencePrefixes = [
    'feed_auto_translate_',
    'feed_silent_',
    'feed_auto_readability_',
  ];

  static const _fixedKeys = {
    StorageKeys.sessionToken,
    StorageKeys.clientId,
    StorageKeys.sessionId,
    StorageKeys.readSyncWindowDays,
    StorageKeys.badgeStrategy,
    StorageKeys.articleContentMaxWidth,
    StorageKeys.macosMaxFlingVelocity,
    _deepseekApiKey,
    _autoRetryMaxCount,
    _translationPrompt,
    _summaryPrompt,
    _filterPrompt,
  };

  static const _stringKeys = {
    StorageKeys.sessionToken,
    StorageKeys.clientId,
    StorageKeys.sessionId,
    StorageKeys.badgeStrategy,
    _deepseekApiKey,
    _translationPrompt,
    _summaryPrompt,
    _filterPrompt,
  };

  static const _intKeys = {
    StorageKeys.readSyncWindowDays,
    StorageKeys.articleContentMaxWidth,
    StorageKeys.macosMaxFlingVelocity,
    _autoRetryMaxCount,
  };

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
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      throw const FormatException('剪贴板没有可导入的配置 JSON');
    }
    return importFromJson(text);
  }

  static Future<SettingsBackupSummary> importFromJson(String text) async {
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException('配置 JSON 顶层必须是对象');
    }

    if (decoded['type'] != backupType) {
      throw const FormatException('不是 Auto Folo 设置备份');
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
      if (key is! String || !_isManagedKey(key)) continue;
      settings[key] = _normalizeValue(key, entry.value);
    }

    await _replaceManagedSettings(settings);
    _refreshRuntimeCaches();
    return summarize(settings);
  }

  static SettingsBackupSummary summarize(Map<String, dynamic> settings) {
    final feedPreferenceCount = settings.keys
        .where((key) => _startsWithAny(key, _feedPreferencePrefixes))
        .length;
    final hasFoloCredentials =
        (settings[StorageKeys.sessionToken] as String?)?.isNotEmpty == true &&
        (settings[StorageKeys.clientId] as String?)?.isNotEmpty == true &&
        (settings[StorageKeys.sessionId] as String?)?.isNotEmpty == true;
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
      if (key is String && _isManagedKey(key)) {
        keysToDelete.add(key);
      }
    }

    for (final key in keysToDelete) {
      await GStorage.setting.delete(key);
    }
    await GStorage.setting.putAll(settings);

    if (keysToDelete.any((key) => key.startsWith('feed_silent_')) ||
        settings.keys.any((key) => key.startsWith('feed_silent_'))) {
      FeedSilentSettingsService.version.value++;
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

  static bool _startsWithAny(String key, List<String> prefixes) {
    return prefixes.any(key.startsWith);
  }

  static bool _isJsonPrimitive(Object? value) {
    return value == null || value is String || value is num || value is bool;
  }

  static dynamic _normalizeValue(String key, Object? value) {
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

    if (key.endsWith('thinking') ||
        _startsWithAny(key, _feedPreferencePrefixes)) {
      if (value is bool) return value;
      throw FormatException('$key 必须是布尔值');
    }

    throw FormatException('不支持的配置项：$key');
  }
}
