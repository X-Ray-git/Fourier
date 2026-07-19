import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../common/widgets/feedback_toast.dart';
import '../http/feed_http.dart';
import '../http/init.dart';
import '../models/article.dart';
import '../pages/article/article_page.dart';
import '../pages/timeline/timeline_controller.dart';
import '../utils/storage.dart';
import 'article_state_notifier.dart';
import 'auto_filter_worker.dart';
import 'batch_read_sync_service.dart';
import 'bounded_history.dart';
import 'local_article_db_service.dart';
import 'read_sync_service.dart';

enum UndoActionType { read, batchRead, filterReject, filterKeep }

class UndoAction {
  UndoAction({
    required this.sequence,
    required this.type,
    required ArticleModel article,
  }) : articles = List.unmodifiable([article]);

  UndoAction.batchRead({
    required this.sequence,
    required List<ArticleModel> articles,
  }) : type = UndoActionType.batchRead,
       articles = List.unmodifiable(articles) {
    assert(articles.isNotEmpty);
  }

  final int sequence;
  final UndoActionType type;
  final List<ArticleModel> articles;

  ArticleModel get article => articles.first;

  String get actionName => switch (type) {
    UndoActionType.read => '标为已读',
    UndoActionType.batchRead => '批量标为已读',
    UndoActionType.filterReject => '从垃圾拦截移除',
    UndoActionType.filterKeep => '在垃圾拦截中保留',
  };

  String get description => switch (type) {
    UndoActionType.read => '将《${article.title}》标为已读',
    UndoActionType.batchRead => '将 ${articles.length} 篇静默文章标为已读',
    UndoActionType.filterReject => '从垃圾拦截移除《${article.title}》',
    UndoActionType.filterKeep => '在垃圾拦截中保留《${article.title}》',
  };
}

class UndoRestoreEvent {
  const UndoRestoreEvent({
    required this.sequence,
    required this.type,
    required this.article,
  });

  final int sequence;
  final UndoActionType type;
  final ArticleModel article;
}

typedef UndoRedoTargetPredicate = bool Function();
typedef RedoPreparation = bool? Function(UndoAction action);

class UndoService {
  static const int historyLimit = 50;

  static final _history = BoundedHistory<UndoAction>(limit: historyLimit);
  static final Map<Object, _RedoPreparationTarget> _redoTargets = {};
  static int _actionSequence = 0;
  static int _restoreSequence = 0;
  static Future<void> _operationTail = Future<void>.value();

  static final restoredAction = Rxn<UndoRestoreEvent>();
  static final historyRevision = ValueNotifier<int>(0);

  static bool get canUndo => _history.canUndo;
  static bool get canRedo => _history.canRedo;
  static UndoAction? get nextUndoAction => _history.nextUndo;
  static UndoAction? get nextRedoAction => _history.nextRedo;

  static ArticleModel? get lastReadArticle {
    final action = _history.nextUndo;
    return action?.type == UndoActionType.read ? action?.article : null;
  }

  static void registerRedoPreparation(
    Object owner, {
    required UndoRedoTargetPredicate isActive,
    required RedoPreparation prepare,
  }) {
    _redoTargets[owner] = _RedoPreparationTarget(
      isActive: isActive,
      prepare: prepare,
    );
  }

  static void unregisterRedoPreparation(Object owner) {
    _redoTargets.remove(owner);
  }

  static void recordRead(ArticleModel article) {
    _record(UndoActionType.read, article);
  }

  static void recordBatchRead(List<ArticleModel> articles) {
    if (articles.isEmpty) return;
    _history.push(
      UndoAction.batchRead(sequence: ++_actionSequence, articles: articles),
    );
    _notifyHistoryChanged();
  }

  static void recordFilterAction(ArticleModel article, UndoActionType type) {
    assert(type != UndoActionType.read);
    _record(type, article);
  }

  static void _record(UndoActionType type, ArticleModel article) {
    _history.push(
      UndoAction(sequence: ++_actionSequence, type: type, article: article),
    );
    _notifyHistoryChanged();
  }

  static void clear() {
    if (!canUndo && !canRedo) return;
    _history.clear();
    _notifyHistoryChanged();
  }

  static void clearForEntry(String entryId) {
    final hadHistory = canUndo || canRedo;
    _history.removeWhere(
      (action) => action.articles.any((article) => article.entryId == entryId),
    );
    if (hadHistory) _notifyHistoryChanged();
  }

  static void _notifyHistoryChanged() {
    historyRevision.value++;
  }

  static void _notifyRestored(UndoAction action) {
    restoredAction.value = UndoRestoreEvent(
      sequence: ++_restoreSequence,
      type: action.type,
      article: action.article,
    );
  }

  static void applyReadLocally(
    ArticleModel article, {
    bool recordHistory = true,
    bool deferTimelineVisualUpdate = false,
    bool queueSync = true,
  }) {
    if (article.entryId.trim().isEmpty) return;
    if (recordHistory) recordRead(article);

    if (Get.isRegistered<TimelineController>()) {
      Get.find<TimelineController>().markAsReadLocal(
        article.entryId,
        deferVisualUpdateToFrameBoundary: deferTimelineVisualUpdate,
        deferArticleStateNotification: deferTimelineVisualUpdate,
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
    if (Get.isRegistered<ArticleController>(tag: article.entryId)) {
      Get.find<ArticleController>(tag: article.entryId).isRead.value = true;
    }

    if (queueSync) {
      ReadSyncService.enqueue(
        article.entryId,
        isInbox: article.category == 'inbox',
      );
      unawaited(ReadSyncService.syncPendingReads());
    }
  }

  static void applyFilterKeep(
    ArticleModel article, {
    bool recordHistory = true,
  }) {
    if (recordHistory) {
      recordFilterAction(article, UndoActionType.filterKeep);
    }
    AutoFilterWorker.unReject(article.entryId);
    GStorage.readStatus.delete(article.entryId);
    _refreshTimelineArticleFromCache(article.entryId);
  }

  static void applyFilterReject(
    ArticleModel article, {
    bool recordHistory = true,
  }) {
    if (recordHistory) {
      recordFilterAction(article, UndoActionType.filterReject);
    }
    LocalArticleDbService.upsertOne(
      _copyArticle(article, isRead: article.isRead, filterReviewed: true),
    );
    applyReadLocally(article, recordHistory: false);
    ArticleStateNotifier.tick(article.entryId);
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

    applyReadLocally(
      article,
      deferTimelineVisualUpdate: deferTimelineVisualUpdate,
      queueSync: false,
    );

    final isInbox = article.category == 'inbox';
    final ok = await _retrySync(
      action: () =>
          FeedHttp.markRead(entryIds: [article.entryId], isInbox: isInbox),
    );

    ReadSyncService.removeMany([article.entryId]);

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

  static Future<BatchReadSyncResult> markBatchAsRead(
    List<ArticleModel> source,
  ) {
    return _enqueueOperation(() async {
      final articles = _uniqueUnreadArticles(source);
      final result = await _syncBatchReadState(articles, isRead: true);
      if (result.changedArticles.isNotEmpty) {
        _applyBatchReadLocally(result.changedArticles, isRead: true);
        recordBatchRead(result.changedArticles);
      }
      return result;
    });
  }

  static List<ArticleModel> _uniqueUnreadArticles(
    Iterable<ArticleModel> source,
  ) {
    final byId = <String, ArticleModel>{};
    for (final article in source) {
      if (article.entryId.trim().isEmpty || article.isRead) continue;
      byId[article.entryId] = article;
    }
    return byId.values.toList(growable: false);
  }

  static void _applyBatchReadLocally(
    List<ArticleModel> articles, {
    required bool isRead,
  }) {
    if (Get.isRegistered<TimelineController>()) {
      Get.find<TimelineController>().setManyReadStatesLocal(
        articles,
        isRead: isRead,
      );
    } else {
      for (final article in articles) {
        if (isRead) {
          GStorage.readStatus.put(article.entryId, true);
        } else {
          GStorage.readStatus.delete(article.entryId);
        }
        LocalArticleDbService.setReadState(
          article.entryId,
          isRead,
          recordHistory: isRead,
        );
      }
      ArticleStateNotifier.tickAll();
    }

    for (final article in articles) {
      if (Get.isRegistered<ArticleController>(tag: article.entryId)) {
        Get.find<ArticleController>(tag: article.entryId).isRead.value = isRead;
      }
    }
  }

  static Future<BatchReadSyncResult> _syncBatchReadState(
    List<ArticleModel> articles, {
    required bool isRead,
  }) {
    return BatchReadSyncService.transition(
      articles,
      targetIsRead: isRead,
      markRead: (chunk, {required isInbox}) {
        return _retrySync(
          action: () => FeedHttp.markRead(
            entryIds: chunk.map((article) => article.entryId).toList(),
            isInbox: isInbox,
          ),
        );
      },
      markUnread: (article) {
        return _retrySync(
          action: () => FeedHttp.markUnread(entryId: article.entryId),
        );
      },
    );
  }

  static Future<ArticleModel?> undoLastAction() {
    return _enqueueOperation(_undoLastAction);
  }

  static Future<ArticleModel?> _undoLastAction() async {
    final action = _history.takeUndo();
    if (action == null) return null;
    _notifyHistoryChanged();

    if (action.type == UndoActionType.batchRead) {
      final result = await _syncBatchReadState(action.articles, isRead: false);
      final restored = result.changedArticles;
      if (restored.isEmpty) {
        _rollbackUndo(action);
        AppFeedback.error('撤销失败', '服务端状态未改变，整批文章仍为已读');
        return null;
      }
      _applyBatchReadLocally(restored, isRead: false);

      if (result.allApplied) {
        AppFeedback.success('已撤销', '已恢复 ${restored.length} 篇静默文章为未读');
      } else {
        final remaining = result.unchangedArticles;
        final resolved = _history.resolvePartialUndo(
          action,
          undonePart: _batchSubset(action, restored),
          remainingPart: _batchSubset(action, remaining),
        );
        if (!resolved) throw StateError('无法拆分部分撤销历史');
        _notifyHistoryChanged();
        AppFeedback.warning(
          '部分撤销',
          '已恢复 ${restored.length} 篇；${remaining.length} 篇仍为已读，可再次撤销',
        );
      }
      return restored.first;
    }

    final article = action.article;

    if (action.type == UndoActionType.filterKeep) {
      LocalArticleDbService.upsertOne(article);
      _replaceTimelineArticle(article);
      ArticleStateNotifier.tick(article.entryId);
      _notifyRestored(action);
      AppFeedback.success('已撤销', '文章已重新移入拦截列表');
      return article;
    }

    if (action.type == UndoActionType.filterReject) {
      LocalArticleDbService.upsertOne(article);
    }

    if (Get.isRegistered<ArticleController>(tag: article.entryId)) {
      final controller = Get.find<ArticleController>(tag: article.entryId);
      await controller.markAsUnread();
      if (!controller.isRead.value) {
        _notifyRestored(action);
        return article;
      }
      _rollbackUndo(action);
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
        LocalArticleDbService.upsertOne(
          _copyArticle(article, isRead: true, filterReviewed: true),
        );
      }
      _rollbackUndo(action);
      AppFeedback.error('撤销失败', '网络请求失败，已恢复为已读');
      return null;
    }

    AppFeedback.success('已撤销', '文章已恢复为未读状态');
    return article;
  }

  static Future<ArticleModel?> redoLastAction() {
    return _enqueueOperation(_redoLastAction);
  }

  static Future<ArticleModel?> _redoLastAction() async {
    final action = _history.nextRedo;
    if (action == null) return null;
    if (!_prepareRedo(action)) return null;

    if (action.type == UndoActionType.batchRead) {
      final result = await _syncBatchReadState(action.articles, isRead: true);
      final redoneArticles = result.changedArticles;
      if (redoneArticles.isEmpty) {
        AppFeedback.error('重做失败', '服务端状态未改变，整批文章仍为未读');
        return null;
      }
      _applyBatchReadLocally(redoneArticles, isRead: true);

      if (result.allApplied) {
        final redone = _history.takeRedo();
        if (!identical(redone, action)) return null;
        _notifyHistoryChanged();
        AppFeedback.success('已重做', action.description);
      } else {
        final remaining = result.unchangedArticles;
        final resolved = _history.resolvePartialRedo(
          action,
          redonePart: _batchSubset(action, redoneArticles),
          remainingPart: _batchSubset(action, remaining),
        );
        if (!resolved) throw StateError('无法拆分部分重做历史');
        _notifyHistoryChanged();
        AppFeedback.warning(
          '部分重做',
          '已标记 ${redoneArticles.length} 篇；${remaining.length} 篇仍为未读，可再次重做',
        );
      }
      return redoneArticles.first;
    }

    switch (action.type) {
      case UndoActionType.read:
        applyReadLocally(
          action.article,
          recordHistory: false,
          deferTimelineVisualUpdate: true,
        );
        break;
      case UndoActionType.batchRead:
        throw StateError('批量重做应在 switch 前处理');
      case UndoActionType.filterReject:
        applyFilterReject(action.article, recordHistory: false);
        break;
      case UndoActionType.filterKeep:
        applyFilterKeep(action.article, recordHistory: false);
        break;
    }

    final redone = _history.takeRedo();
    if (!identical(redone, action)) return null;
    _notifyHistoryChanged();
    AppFeedback.success('已重做', action.description);
    return action.article;
  }

  static bool _prepareRedo(UndoAction action) {
    for (final target in _redoTargets.values.toList().reversed) {
      if (!target.isActive()) continue;
      final result = target.prepare(action);
      if (result != null) return result;
    }
    return true;
  }

  static Future<T> _enqueueOperation<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  static void _rollbackUndo(UndoAction action) {
    if (_history.rollbackUndo(action)) _notifyHistoryChanged();
  }

  static UndoAction _batchSubset(
    UndoAction original,
    List<ArticleModel> articles,
  ) {
    return UndoAction.batchRead(
      sequence: original.sequence,
      articles: articles,
    );
  }

  static void _refreshTimelineArticleFromCache(String entryId) {
    if (!Get.isRegistered<TimelineController>()) return;
    final raw = GStorage.articleDb.get(entryId);
    if (raw is! Map) return;
    _replaceTimelineArticle(
      ArticleModel.fromCache(Map<String, dynamic>.from(raw)),
    );
  }

  static void _replaceTimelineArticle(ArticleModel article) {
    if (!Get.isRegistered<TimelineController>()) return;
    final controller = Get.find<TimelineController>();
    final index = controller.allArticles.indexWhere(
      (candidate) => candidate.entryId == article.entryId,
    );
    if (index < 0) return;
    controller.allArticles[index] = article;
    controller.allArticles.refresh();
  }

  static ArticleModel _copyArticle(
    ArticleModel article, {
    required bool isRead,
    required bool filterReviewed,
  }) {
    return ArticleModel(
      entryId: article.entryId,
      feedId: article.feedId,
      feedTitle: article.feedTitle,
      feedImage: article.feedImage,
      title: article.title,
      url: article.url,
      content: article.content,
      publishedAt: article.publishedAt,
      isRead: isRead,
      category: article.category,
      subscriptionCategory: article.subscriptionCategory,
      author: article.author,
      imageUrl: article.imageUrl,
      isRejectedByAi: article.isRejectedByAi,
      filterReason: article.filterReason,
      filterReviewed: filterReviewed,
      filteredAt: article.filteredAt,
    );
  }

  static Future<bool> _retrySync({
    required Future<LoadingState<void>> Function() action,
  }) async {
    for (var attempt = 1; attempt <= 5; attempt++) {
      final result = await action();
      if (result is Success<void>) return true;
      if (attempt < 5) {
        await Future<void>.delayed(Duration(milliseconds: 800 * attempt));
      }
    }
    return false;
  }
}

class _RedoPreparationTarget {
  const _RedoPreparationTarget({required this.isActive, required this.prepare});

  final UndoRedoTargetPredicate isActive;
  final RedoPreparation prepare;
}
