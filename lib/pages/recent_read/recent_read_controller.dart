import 'package:get/get.dart';

import '../../http/init.dart';
import '../../models/article.dart';
import '../../services/article_state_notifier.dart';
import '../../services/local_article_db_service.dart';
import '../../utils/storage.dart';

/// 最近阅读控制器
class RecentReadController extends GetxController {
  final loadingState = Rx<LoadingState<List<ArticleModel>>>(const Loading());
  final articles = <ArticleModel>[].obs;
  final allArticles = <ArticleModel>[].obs;
  late final Worker _articleStateWorker;

  @override
  void onInit() {
    super.onInit();

    // 监听全局文章状态变更（例如在 Timeline 中将某篇文章标记为已读或未读）
    _articleStateWorker = ever(ArticleStateNotifier.version, (_) {
      _loadData();
    });

    _loadData();
  }

  @override
  void onClose() {
    _articleStateWorker.dispose();
    super.onClose();
  }

  void _loadData() {
    if (allArticles.isEmpty) loadingState.value = const Loading();

    // 获取本地所有文章
    final local = LocalArticleDbService.readAllArticles();

    // 过滤出所有已读文章，并合并覆盖状态
    final readArticles = LocalArticleDbService.mergeReadOverrides(
      local,
    ).where((a) => a.isRead).toList();

    // 按照历史阅读时间降序排序
    readArticles.sort((a, b) {
      final timeA = GStorage.readHistory.get(a.entryId) as int?;
      final timeB = GStorage.readHistory.get(b.entryId) as int?;

      // 如果都有时间戳，按时间戳倒序
      if (timeA != null && timeB != null) {
        return timeB.compareTo(timeA);
      }
      // A有，B没有，A排前面
      if (timeA != null && timeB == null) return -1;
      // B有，A没有，B排前面
      if (timeA == null && timeB != null) return 1;

      // 都没有时间戳，回退到按发布时间排序
      final pubA = _timeScore(a.publishedAt);
      final pubB = _timeScore(b.publishedAt);
      return pubB.compareTo(pubA);
    });

    allArticles.value = readArticles;
    articles.value = readArticles;

    loadingState.value = Success(articles.toList());
  }

  int _timeScore(String publishedAt) {
    final raw = publishedAt.trim();
    if (raw.isEmpty) return 0;
    return DateTime.tryParse(raw)?.millisecondsSinceEpoch ?? 0;
  }

  void refreshData() {
    _loadData();
  }
}
