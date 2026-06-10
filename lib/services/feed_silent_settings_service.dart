import 'package:get/get.dart';

import '../utils/storage.dart';

/// 管理每个订阅源的静默设置
abstract final class FeedSilentSettingsService {
  static const String _keyPrefix = 'feed_silent_';

  /// 用于通知 UI 层（如侧边栏分类树）配置已变更
  static final RxInt version = 0.obs;

  static bool isSilent(String feedId) {
    if (feedId.isEmpty) return false;
    final stored = GStorage.setting.get('$_keyPrefix$feedId');
    return stored is bool ? stored : false;
  }

  static Future<void> setSilent(String feedId, bool silent) async {
    if (feedId.isEmpty) return;
    await GStorage.setting.put('$_keyPrefix$feedId', silent);
    version.value++;
  }

  static Future<void> toggleSilent(String feedId) async {
    if (feedId.isEmpty) return;
    final current = isSilent(feedId);
    await setSilent(feedId, !current);
  }

  static Future<void> clearAllSettings() async {
    final keysToDelete = <String>[];
    for (final key in GStorage.setting.keys) {
      if (key is String && key.startsWith(_keyPrefix)) {
        keysToDelete.add(key);
      }
    }
    for (final key in keysToDelete) {
      await GStorage.setting.delete(key);
    }
    if (keysToDelete.isNotEmpty) {
      version.value++;
    }
  }
}
