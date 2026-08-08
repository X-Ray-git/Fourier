import '../models/article.dart';
import '../utils/storage.dart';
import 'auto_summary_worker.dart';
import 'auto_translation_worker.dart';

/// 正文可用后，统一判断文章是否应进入自动 AI 队列。
abstract final class AutoAiQueueCoordinator {
  /// 正文补全后，按最新持久化状态把文章流转到自动 AI 队列。
  ///
  /// [allowRead] 供「已开始的全文抓取流水线」使用：文章未读时已开始
  /// 抓取，即使完成前被标为已读，也允许这一条已开始的流水线继续进入
  /// 翻译和摘要；尚未开始的等待任务在出队时已被移除。
  static void onArticleContentAvailable(
    ArticleModel article, {
    bool allowRead = false,
  }) {
    if (article.entryId.trim().isEmpty) return;
    if ((article.content ?? '').trim().isEmpty) return;

    if (!allowRead) {
      final latest = GStorage.articleDb.get(article.entryId);
      final isCurrentlyRead = latest is Map
          ? latest['isRead'] == true
          : article.isRead;
      if (isCurrentlyRead) return;
    }

    AutoTranslationWorker.enqueueIfEnabled(article);
    AutoSummaryWorker.enqueueIfNeeded(article);
  }
}
