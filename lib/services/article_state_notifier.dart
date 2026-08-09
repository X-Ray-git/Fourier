import 'package:get/get.dart';

/// 全局文章状态变更通知器。
/// 调用 [tick(entryId)] 通知所有监听页该文章状态已变。
abstract final class ArticleStateNotifier {
  static final version = 0.obs;
  static String? _lastEntryId;

  /// 最近一次变更的 entryId；[tickAll] 会将其清空。
  static String? get lastEntryId => _lastEntryId;

  static void tick(String entryId) {
    _lastEntryId = entryId;
    version.value++;
  }

  /// 通知消费者重读整个可见集合，避免批量操作逐篇触发重建。
  static void tickAll() {
    _lastEntryId = null;
    version.value++;
  }
}
