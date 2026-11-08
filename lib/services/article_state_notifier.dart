import 'package:get/get.dart';

/// 全局文章状态变更通知器。
/// 调用 [tick(entryId)] 通知所有监听页该文章状态已变。
abstract final class ArticleStateNotifier {
  static final version = 0.obs;
  static final Map<String, RxInt> _articleVersions = <String, RxInt>{};
  static String? _lastEntryId;

  /// 最近一次变更的 entryId；[tickAll] 会将其清空。
  static String? get lastEntryId => _lastEntryId;

  /// Reactive version for one article's locally persisted state.
  ///
  /// Consumers that render a single article should observe this instead of
  /// [version], otherwise an unrelated article update fans out into their
  /// whole subtree.
  static RxInt versionFor(String entryId) {
    return _articleVersions.putIfAbsent(entryId, () => 0.obs);
  }

  /// A classification update does not change unread counts or feed membership.
  static void notifyArticleObserver(String entryId) {
    final observer = _articleVersions[entryId];
    if (observer != null) observer.value++;
  }

  static void tick(String entryId) {
    _lastEntryId = entryId;
    version.value++;
    versionFor(entryId).value++;
  }

  /// 通知消费者重读整个可见集合，避免批量操作逐篇触发重建。
  static void tickAll() {
    _lastEntryId = null;
    version.value++;
    for (final articleVersion in _articleVersions.values.toList(
      growable: false,
    )) {
      articleVersion.value++;
    }
  }
}
