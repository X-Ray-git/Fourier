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

enum UndoActionType { read, filterReject, filterKeep }

class UndoAction {
  final UndoActionType type;
  final ArticleModel article;

  UndoAction(this.type, this.article);
}

class UndoRestoreEvent {
  final int sequence;
  final UndoActionType type;
  final ArticleModel article;

  const UndoRestoreEvent({
    required this.sequence,
    required this.type,
    required this.article,
  });
}

class UndoService {
  static UndoAction? _lastAction;
  static int _restoreSequence = 0;
  static final restoredAction = Rxn<UndoRestoreEvent>();

  static ArticleModel? get lastReadArticle =>
      _lastAction?.type == UndoActionType.read ? _lastAction?.article : null;

  static void recordRead(ArticleModel article) {
    _lastAction = UndoAction(UndoActionType.read, article);
  }

  static void recordFilterAction(ArticleModel article, UndoActionType type) {
    _lastAction = UndoAction(type, article);
  }

  static void clear() {
    _lastAction = null;
  }

  static void clearForEntry(String entryId) {
    if (_lastAction?.article.entryId == entryId) {
      _lastAction = null;
    }
  }

  static void _notifyRestored(UndoAction action) {
    restoredAction.value = UndoRestoreEvent(
      sequence: ++_restoreSequence,
      type: action.type,
      article: action.article,
    );
  }

  static Future<void> markAsRead(
    ArticleModel article, {
    bool showSuccess = true,
    bool deferTimelineVisualUpdate = false,
  }) async {
    if (article.isRead || article.entryId.trim().isEmpty) return;
    if (!deferTimelineVisualUpdate &&
        Get.isRegistered<ArticleController>(tag: article.entryId)) {
      await Get.find<ArticleController>(
        tag: article.entryId,
      ).markAsRead(showSuccess: showSuccess);
      return;
    }

    recordRead(article);

    if (Get.isRegistered<TimelineController>()) {
      Get.find<TimelineController>().markAsReadLocal(
        article.entryId,
        deferVisualUpdateToFrameBoundary: deferTimelineVisualUpdate,
      );
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

  static Future<ArticleModel?> undoLastAction() async {
    final action = _lastAction;
    if (action == null) return null;
    _lastAction = null;

    final article = action.article;

    if (action.type == UndoActionType.filterKeep) {
      // Undo a KEEP action: restore the AI reject status. No network calls.
      LocalArticleDbService.upsertOne(article);
      if (Get.isRegistered<TimelineController>()) {
        final tc = Get.find<TimelineController>();
        final idx = tc.allArticles.indexWhere(
          (a) => a.entryId == article.entryId,
        );
        if (idx >= 0) {
          tc.allArticles[idx] = article;
          tc.allArticles.refresh();
        }
      }
      ArticleStateNotifier.tick(article.entryId);
      _notifyRestored(action);
      AppFeedback.success('已撤销', '文章已重新移入拦截列表');
      return article;
    }

    // Both 'read' and 'filterReject' mark the article as read. We must revert to unread.
    if (action.type == UndoActionType.filterReject) {
      // Restore to the original filterReviewed:false state.
      LocalArticleDbService.upsertOne(article);
    }

    if (Get.isRegistered<ArticleController>(tag: article.entryId)) {
      final controller = Get.find<ArticleController>(tag: article.entryId);
      await controller.markAsUnread();
      if (!controller.isRead.value) {
        _notifyRestored(action);
        return article;
      }
      return null;
    }

    if (Get.isRegistered<TimelineController>()) {
      Get.find<TimelineController>().markAsUnreadLocal(article.entryId);
    } else {
      LocalArticleDbService.setReadState(article.entryId, false);
      ArticleStateNotifier.tick(article.entryId);
    }
    _notifyRestored(action);

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
      if (action.type == UndoActionType.filterReject) {
        // Re-apply filterReviewed:true since the network request failed
        LocalArticleDbService.upsertOne(
          ArticleModel(
            entryId: article.entryId,
            feedId: article.feedId,
            feedTitle: article.feedTitle,
            feedImage: article.feedImage,
            title: article.title,
            url: article.url,
            content: article.content,
            publishedAt: article.publishedAt,
            isRead: true,
            category: article.category,
            subscriptionCategory: article.subscriptionCategory,
            author: article.author,
            imageUrl: article.imageUrl,
            isRejectedByAi: article.isRejectedByAi,
            filterReason: article.filterReason,
            filterReviewed: true,
            filteredAt: article.filteredAt,
          ),
        );
      }
      AppFeedback.error('撤销失败', '网络请求失败，已恢复为已读');
      return null;
    }

    AppFeedback.success('已撤销', '文章已恢复为未读状态');
    return article;
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
