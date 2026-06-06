import 'package:get/get.dart';
import '../models/article.dart';
import '../pages/article/article_page.dart';
import '../pages/timeline/timeline_controller.dart';
import '../services/local_article_db_service.dart';
import '../services/article_state_notifier.dart';
import '../services/read_sync_service.dart';
import '../http/feed_http.dart';
import '../http/init.dart';
import '../common/widgets/feedback_toast.dart';
import '../utils/storage.dart';

class UndoService {
  static ArticleModel? _lastReadArticle;

  static ArticleModel? get lastReadArticle => _lastReadArticle;

  static void recordRead(ArticleModel article) {
    _lastReadArticle = article;
  }

  static void clear() {
    _lastReadArticle = null;
  }

  static void clearForEntry(String entryId) {
    if (_lastReadArticle?.entryId == entryId) {
      _lastReadArticle = null;
    }
  }

  static Future<void> markAsRead(
    ArticleModel article, {
    bool showSuccess = true,
  }) async {
    if (article.isRead || article.entryId.trim().isEmpty) return;
    if (Get.isRegistered<ArticleController>(tag: article.entryId)) {
      await Get.find<ArticleController>(
        tag: article.entryId,
      ).markAsRead(showSuccess: showSuccess);
      return;
    }

    recordRead(article);
    if (article.isRejectedByAi) {
      LocalArticleDbService.clearFilterState(article.entryId);
    }

    if (Get.isRegistered<TimelineController>()) {
      Get.find<TimelineController>().markAsReadLocal(article.entryId);
    } else {
      GStorage.readStatus.put(article.entryId, true);
      LocalArticleDbService.setReadState(
        article.entryId,
        true,
        recordHistory: true,
      );
      ArticleStateNotifier.tick(article.entryId);
    }

    final isInbox = article.category == 'inbox';
    ReadSyncService.enqueue(article.entryId, isInbox: isInbox);

    final ok = await _retrySync(
      action: () =>
          FeedHttp.markRead(entryIds: [article.entryId], isInbox: isInbox),
    );

    ReadSyncService.removeMany([article.entryId]);
    GStorage.readStatus.delete(article.entryId);

    if (!ok) {
      clearForEntry(article.entryId);
      if (Get.isRegistered<TimelineController>()) {
        Get.find<TimelineController>().markAsUnreadLocal(article.entryId);
      } else {
        LocalArticleDbService.setReadState(article.entryId, false);
        ArticleStateNotifier.tick(article.entryId);
      }
      AppFeedback.error('标记已读失败', '已重试5次，已恢复为未读');
      return;
    }

    if (showSuccess) {
      AppFeedback.success('已标记已读', '已同步到云端');
    }
  }

  static Future<void> undoLastRead() async {
    final article = _lastReadArticle;
    if (article == null) return;
    _lastReadArticle = null;

    if (Get.isRegistered<ArticleController>(tag: article.entryId)) {
      await Get.find<ArticleController>(tag: article.entryId).markAsUnread();
      return;
    }

    if (Get.isRegistered<TimelineController>()) {
      Get.find<TimelineController>().markAsUnreadLocal(article.entryId);
    } else {
      LocalArticleDbService.setReadState(article.entryId, false);
      ArticleStateNotifier.tick(article.entryId);
    }

    final ok = await _retrySync(
      action: () => FeedHttp.markUnread(entryId: article.entryId),
    );

    if (!ok) {
      if (Get.isRegistered<TimelineController>()) {
        Get.find<TimelineController>().markAsReadLocal(
          article.entryId,
          recordHistory: false,
        );
      } else {
        LocalArticleDbService.setReadState(article.entryId, true);
        ArticleStateNotifier.tick(article.entryId);
      }
      AppFeedback.error('撤销失败', '网络请求失败，已恢复为已读');
      return;
    }

    AppFeedback.success('已撤销', '文章已恢复为未读状态');
  }

  static Future<bool> _retrySync({
    required Future<LoadingState<void>> Function() action,
  }) async {
    for (int attempt = 1; attempt <= 5; attempt++) {
      final result = await action();
      if (result is Success<void>) {
        return true;
      }
      if (attempt < 5) {
        await Future.delayed(Duration(milliseconds: 800 * attempt));
      }
    }
    return false;
  }
}
