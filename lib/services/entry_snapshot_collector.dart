import '../http/init.dart';
import '../models/article.dart';
import 'analysis_event_ledger.dart';
import 'account_session_guard.dart';

class EntrySnapshotResult extends Success<List<ArticleModel>> {
  const EntrySnapshotResult(
    super.response, {
    required this.isComplete,
    this.auditSequence,
  });
  final bool isComplete;
  final int? auditSequence;
}

/// A successful page/partial collection is not necessarily a complete unread
/// snapshot. Only normal exhaustion may infer missing articles as read.
abstract final class EntrySnapshotCollector {
  static bool isComplete(LoadingState<List<ArticleModel>> result) =>
      result is Success<List<ArticleModel>> &&
      (result is! EntrySnapshotResult || result.isComplete);

  static int? sequenceOf(LoadingState<List<ArticleModel>> result) =>
      result is EntrySnapshotResult ? result.auditSequence : null;

  static EntrySnapshotResult result(
    List<ArticleModel> items, {
    required String source,
    required bool read,
    required bool complete,
    required String stopReason,
    required int limit,
    required List<Map<String, Object?>> pages,
    List<int>? childSequences,
  }) => EntrySnapshotResult(
    items,
    isComplete: complete,
    auditSequence: AnalysisEventLedger.recordEntrySnapshot(
      source: source,
      read: read,
      complete: complete,
      stopReason: stopReason,
      limit: limit,
      count: items.length,
      pages: pages,
      childSequences: childSequences,
    ),
  );

  static Future<LoadingState<List<ArticleModel>>> collect({
    required String source,
    required bool read,
    required int limit,
    required Future<LoadingState<List<ArticleModel>>> Function(String? cursor)
    loadPage,
    String? initialCursor,
    int? maxPages,
  }) async {
    final accountRevision = AccountSessionGuard.revision;
    final items = <ArticleModel>[];
    final seen = <String>{};
    final pages = <Map<String, Object?>>[];
    var cursor = initialCursor;
    EntrySnapshotResult finish(bool complete, String reason) => result(
      items,
      source: source,
      read: read,
      complete: complete,
      stopReason: reason,
      limit: limit,
      pages: pages,
    );
    while (true) {
      if (!AccountSessionGuard.isCurrent(accountRevision)) {
        return const LoadError('账号已变化');
      }
      if (maxPages != null && pages.length >= maxPages) {
        return finish(false, 'page_limit');
      }
      final LoadingState<List<ArticleModel>> page;
      try {
        page = await loadPage(cursor);
      } catch (_) {
        if (!AccountSessionGuard.isCurrent(accountRevision)) {
          return const LoadError('账号已变化');
        }
        pages.add({'cursor': cursor, 'success': false});
        final partial = finish(false, 'parse_exception');
        return items.isEmpty ? const LoadError('条目返回数据解析失败') : partial;
      }
      if (!AccountSessionGuard.isCurrent(accountRevision)) {
        return const LoadError('账号已变化');
      }
      if (page is! Success<List<ArticleModel>>) {
        pages.add({
          'cursor': cursor,
          'success': false,
          if (page is LoadError<List<ArticleModel>>) 'statusCode': page.code,
        });
        final partial = finish(false, 'request_failed');
        return items.isEmpty ? page : partial;
      }
      final batch = page.response;
      final before = items.length;
      for (final item in batch) {
        if (item.entryId.isEmpty) return finish(false, 'invalid_entry_id');
        if (seen.add(item.entryId)) items.add(item);
      }
      pages.add({
        'cursor': cursor,
        'success': true,
        'returned': batch.length,
        'newItems': items.length - before,
        if (batch.isNotEmpty) 'firstId': batch.first.entryId,
        if (batch.isNotEmpty) 'lastId': batch.last.entryId,
        if (batch.isNotEmpty) 'lastPublishedAt': batch.last.publishedAt,
      });
      if (batch.isEmpty) return finish(true, 'empty_page');
      if (items.length == before) return finish(false, 'no_progress');
      if (batch.length < limit) return finish(true, 'short_page');
      final next = batch.last.publishedAt;
      if (next.isEmpty) return finish(false, 'missing_cursor');
      if (next == cursor) return finish(false, 'repeated_cursor');
      cursor = next;
    }
  }
}
