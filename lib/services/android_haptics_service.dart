import 'dart:io';

import 'package:flutter/services.dart';

import '../utils/storage.dart';

/// Android 触觉反馈策略服务 — 集中且轻量，macOS 完全不受影响。
///
/// 只在明确的语义动作上振动，普通点击、滚动、加载、AI 完成与动画
/// 一律不振动。开关持久化在设置中，默认开启。
abstract final class AndroidHapticsService {
  static const String enabledKey = 'android_haptics_enabled';

  static bool get isEnabled {
    if (!Platform.isAndroid) return false;
    final raw = GStorage.setting.get(enabledKey);
    return raw is bool ? raw : true;
  }

  static Future<void> setEnabled(bool enabled) =>
      GStorage.setting.put(enabledKey, enabled);

  /// 列表/筛选选择等轻微反馈。
  static Future<void> selectionClick() async {
    if (!isEnabled) return;
    await HapticFeedback.selectionClick();
  }

  /// 已读状态变更成功等轻反馈。
  static Future<void> lightImpact() async {
    if (!isEnabled) return;
    await HapticFeedback.lightImpact();
  }

  /// 侧滑确认等中等反馈。
  static Future<void> mediumImpact() async {
    if (!isEnabled) return;
    await HapticFeedback.mediumImpact();
  }
}
