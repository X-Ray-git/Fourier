import 'auto_summary_worker.dart';
import 'auto_translation_worker.dart';

/// 统一处理文章状态变化对尚未开始的自动 AI 任务的影响。
abstract final class AutoAiQueueCoordinator {
  static void onArticleMarkedRead(String entryId) {
    if (entryId.trim().isEmpty) return;
    AutoTranslationWorker.removeQueued(entryId);
    AutoSummaryWorker.removeQueued(entryId);
  }
}
