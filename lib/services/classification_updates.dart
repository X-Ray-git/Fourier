import 'dart:async';

import 'package:get/get.dart';

import '../models/article.dart';
import 'account_session_guard.dart';
import 'article_state_notifier.dart';
import 'local_article_db_service.dart';

/// Only the UI delivery is coalesced; persistence and per-result accounting
/// are independent. Read the latest row at delivery so a manual action wins.
abstract final class ClassificationUpdates {
  static final _events = StreamController<ClassificationBatch>.broadcast(
    sync: true,
  );
  static Stream<ClassificationBatch> get batches => _events.stream;
  static final _pending = <String>{};
  static Timer? _timer;
  static int? _revision;

  static void enqueue(String entryId) {
    final revision = AccountSessionGuard.revision;
    if (_revision != revision) clear();
    _revision = revision;
    _pending.add(entryId);
    _timer ??= Timer(const Duration(milliseconds: 16), () {
      final ids = _pending.toList();
      clear();
      if (!AccountSessionGuard.isCurrent(revision)) return;
      final rows = <String, ArticleModel>{};
      for (final id in ids) {
        final row = LocalArticleDbService.readArticle(id);
        if (row != null) rows[id] = row;
      }
      if (rows.isEmpty) return;
      _events.add(ClassificationBatch(rows));
      for (final id in rows.keys) {
        ArticleStateNotifier.notifyArticleObserver(id);
      }
    });
  }

  static void clear() {
    _timer?.cancel();
    _timer = null;
    _revision = null;
    _pending.clear();
  }
}

class ClassificationBatch {
  final Map<String, ArticleModel> rows;
  ClassificationBatch(Map<String, ArticleModel> rows)
    : rows = Map.unmodifiable(rows);

  /// Patch classification fields only. A read animation or a detail view can
  /// intentionally hold a different read state/body from the persisted row.
  bool patch(
    RxList<ArticleModel> target, {
    bool Function(ArticleModel)? includeMissing,
  }) {
    final missing = includeMissing == null ? null : Map.of(rows);
    List<ArticleModel>? next;
    for (var i = 0; i < target.length; i++) {
      final a = target[i];
      missing?.remove(a.entryId);
      final row = rows[a.entryId];
      if (row == null ||
          (a.isRejectedByAi == row.isRejectedByAi &&
              a.filteredAt == row.filteredAt &&
              a.filterReason == row.filterReason &&
              a.filterReviewed == row.filterReviewed &&
              a.userAction == row.userAction)) {
        continue;
      }
      (next ??= target.toList())[i] = a.copyWith(
        isRejectedByAi: row.isRejectedByAi,
        filteredAt: row.filteredAt,
        filterReason: row.filterReason,
        filterReviewed: row.filterReviewed,
        userAction: row.userAction,
      );
    }
    if (includeMissing != null) {
      for (final row in missing!.values.where(includeMissing)) {
        (next ??= target.toList()).add(row);
      }
    }
    if (next == null) return false;
    target.value = next;
    return true;
  }
}
