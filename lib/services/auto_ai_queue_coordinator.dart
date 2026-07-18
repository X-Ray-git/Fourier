import '../models/article.dart';
import '../utils/storage.dart';
import 'auto_summary_worker.dart';
import 'auto_translation_worker.dart';

/// 统一处理文章状态变化对尚未开始的自动 AI 任务的影响。
abstract final class AutoAiQueueCoordinator {
  /// 正文补全后，按最新持久化状态把未读文章流转到自动 AI 队列。
  static void onArticleContentAvailable(ArticleModel article) {
    if (article.entryId.trim().isEmpty) return;
    if ((article.content ?? '').trim().isEmpty) return;

    final latest = GStorage.articleDb.get(article.entryId);
    final isCurrentlyRead = latest is Map
        ? latest['isRead'] == true
        : article.isRead;
    if (isCurrentlyRead) return;

    AutoTranslationWorker.enqueueIfEnabled(article);
    AutoSummaryWorker.enqueueIfNeeded(article);
  }

  static void onArticleMarkedRead(String entryId) {
    if (entryId.trim().isEmpty) return;
    AutoTranslationWorker.removeQueued(entryId);
    AutoSummaryWorker.removeQueued(entryId);
  }
}
