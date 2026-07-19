import '../models/article.dart';

typedef BatchMarkRead =
    Future<bool> Function(List<ArticleModel> articles, {required bool isInbox});
typedef BatchMarkUnread = Future<bool> Function(ArticleModel article);

class BatchReadSyncResult {
  const BatchReadSyncResult({
    required this.requestedArticles,
    required this.targetIsRead,
    required this.operationSucceededIds,
    required this.compensationSucceededIds,
    required this.compensationAttempted,
  });

  final List<ArticleModel> requestedArticles;
  final bool targetIsRead;
  final Set<String> operationSucceededIds;
  final Set<String> compensationSucceededIds;
  final bool compensationAttempted;

  bool get allApplied =>
      operationSucceededIds.length == requestedArticles.length &&
      !compensationAttempted;

  List<ArticleModel> get changedArticles => requestedArticles
      .where(
        (article) =>
            operationSucceededIds.contains(article.entryId) &&
            !compensationSucceededIds.contains(article.entryId),
      )
      .toList(growable: false);

  List<ArticleModel> get unchangedArticles => requestedArticles
      .where(
        (article) =>
            !operationSucceededIds.contains(article.entryId) ||
            compensationSucceededIds.contains(article.entryId),
      )
      .toList(growable: false);

  List<ArticleModel> get operationFailedArticles => requestedArticles
      .where((article) => !operationSucceededIds.contains(article.entryId))
      .toList(growable: false);

  List<ArticleModel> get compensationFailedArticles =>
      compensationAttempted ? changedArticles : const <ArticleModel>[];
}

abstract final class BatchReadSyncService {
  static Future<BatchReadSyncResult> transition(
    Iterable<ArticleModel> source, {
    required bool targetIsRead,
    required BatchMarkRead markRead,
    required BatchMarkUnread markUnread,
    int markReadBatchSize = 50,
    int markUnreadConcurrency = 4,
  }) async {
    assert(markReadBatchSize > 0);
    assert(markUnreadConcurrency > 0);

    final byId = <String, ArticleModel>{};
    for (final article in source) {
      if (article.entryId.trim().isEmpty) continue;
      byId[article.entryId] = article;
    }
    final articles = byId.values.toList(growable: false);
    if (articles.isEmpty) {
      return BatchReadSyncResult(
        requestedArticles: articles,
        targetIsRead: targetIsRead,
        operationSucceededIds: const {},
        compensationSucceededIds: const {},
        compensationAttempted: false,
      );
    }

    final operationSucceeded = <String>{};
    final operationComplete = targetIsRead
        ? await _markReadUntilFailure(
            articles,
            markRead: markRead,
            batchSize: markReadBatchSize,
            succeededIds: operationSucceeded,
          )
        : await _markUnreadUntilFailure(
            articles,
            markUnread: markUnread,
            concurrency: markUnreadConcurrency,
            succeededIds: operationSucceeded,
          );

    if (operationComplete) {
      return BatchReadSyncResult(
        requestedArticles: articles,
        targetIsRead: targetIsRead,
        operationSucceededIds: Set.unmodifiable(operationSucceeded),
        compensationSucceededIds: const {},
        compensationAttempted: false,
      );
    }

    final succeededArticles = articles
        .where((article) => operationSucceeded.contains(article.entryId))
        .toList(growable: false);
    final compensationSucceeded = <String>{};
    if (targetIsRead) {
      await _markUnreadForCompensation(
        succeededArticles,
        markUnread: markUnread,
        concurrency: markUnreadConcurrency,
        succeededIds: compensationSucceeded,
      );
    } else {
      await _markReadForCompensation(
        succeededArticles,
        markRead: markRead,
        batchSize: markReadBatchSize,
        succeededIds: compensationSucceeded,
      );
    }

    return BatchReadSyncResult(
      requestedArticles: articles,
      targetIsRead: targetIsRead,
      operationSucceededIds: Set.unmodifiable(operationSucceeded),
      compensationSucceededIds: Set.unmodifiable(compensationSucceeded),
      compensationAttempted: operationSucceeded.isNotEmpty,
    );
  }

  static Future<bool> _markReadUntilFailure(
    List<ArticleModel> articles, {
    required BatchMarkRead markRead,
    required int batchSize,
    required Set<String> succeededIds,
  }) async {
    for (final group in _groupByInbox(articles).entries) {
      for (var start = 0; start < group.value.length; start += batchSize) {
        final end = (start + batchSize).clamp(0, group.value.length);
        final chunk = group.value.sublist(start, end);
        if (!await _tryMarkRead(markRead, chunk, isInbox: group.key)) {
          return false;
        }
        succeededIds.addAll(chunk.map((article) => article.entryId));
      }
    }
    return true;
  }

  static Future<bool> _markUnreadUntilFailure(
    List<ArticleModel> articles, {
    required BatchMarkUnread markUnread,
    required int concurrency,
    required Set<String> succeededIds,
  }) async {
    for (var start = 0; start < articles.length; start += concurrency) {
      final end = (start + concurrency).clamp(0, articles.length);
      final chunk = articles.sublist(start, end);
      final results = await Future.wait(
        chunk.map((article) => _tryMarkUnread(markUnread, article)),
      );
      for (var index = 0; index < results.length; index++) {
        if (results[index]) succeededIds.add(chunk[index].entryId);
      }
      if (results.any((success) => !success)) return false;
    }
    return true;
  }

  static Future<void> _markUnreadForCompensation(
    List<ArticleModel> articles, {
    required BatchMarkUnread markUnread,
    required int concurrency,
    required Set<String> succeededIds,
  }) async {
    for (var start = 0; start < articles.length; start += concurrency) {
      final end = (start + concurrency).clamp(0, articles.length);
      final chunk = articles.sublist(start, end);
      final results = await Future.wait(
        chunk.map((article) => _tryMarkUnread(markUnread, article)),
      );
      for (var index = 0; index < results.length; index++) {
        if (results[index]) succeededIds.add(chunk[index].entryId);
      }
    }
  }

  static Future<void> _markReadForCompensation(
    List<ArticleModel> articles, {
    required BatchMarkRead markRead,
    required int batchSize,
    required Set<String> succeededIds,
  }) async {
    for (final group in _groupByInbox(articles).entries) {
      for (var start = 0; start < group.value.length; start += batchSize) {
        final end = (start + batchSize).clamp(0, group.value.length);
        final chunk = group.value.sublist(start, end);
        if (await _tryMarkRead(markRead, chunk, isInbox: group.key)) {
          succeededIds.addAll(chunk.map((article) => article.entryId));
        }
      }
    }
  }

  static Map<bool, List<ArticleModel>> _groupByInbox(
    List<ArticleModel> articles,
  ) {
    final grouped = <bool, List<ArticleModel>>{};
    for (final article in articles) {
      grouped
          .putIfAbsent(article.category == 'inbox', () => <ArticleModel>[])
          .add(article);
    }
    return grouped;
  }

  static Future<bool> _tryMarkRead(
    BatchMarkRead markRead,
    List<ArticleModel> articles, {
    required bool isInbox,
  }) async {
    try {
      return await markRead(articles, isInbox: isInbox);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _tryMarkUnread(
    BatchMarkUnread markUnread,
    ArticleModel article,
  ) async {
    try {
      return await markUnread(article);
    } catch (_) {
      return false;
    }
  }
}
