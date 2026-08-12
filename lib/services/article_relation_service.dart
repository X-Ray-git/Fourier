import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../common/constants/constants.dart';
import '../models/article.dart';
import '../models/article_relation.dart';
import '../utils/storage.dart';
import 'local_article_db_service.dart';
import 'summary_service.dart';

class ArticleRelationBatchInput {
  const ArticleRelationBatchInput({
    required this.id,
    required this.newNodes,
    required this.historyNodes,
  });

  final String id;
  final List<ArticleRelationNode> newNodes;
  final List<ArticleRelationNode> historyNodes;
}

class ArticleRelationCandidateGroup {
  const ArticleRelationCandidateGroup({
    required this.kind,
    required this.memberIds,
    required this.reason,
    required this.confidence,
  });

  final ArticleRelationKind kind;
  final List<String> memberIds;
  final String reason;
  final double confidence;
}

class ArticleRelationDisplayItem {
  const ArticleRelationDisplayItem({
    required this.node,
    required this.kind,
    this.article,
  });

  final ArticleRelationNode node;
  final ArticleRelationKind kind;
  final ArticleModel? article;
}

/// 文章关系的账号级持久化层。
///
/// 关系功能只消费启用时间之后完成的摘要。pending 与 history 都持久化，
/// 因此请求失败或进程退出不会丢任务；只有一个合法批次完整落盘后才推进窗口。
abstract final class ArticleRelationService {
  static const int schemaVersion = 2;
  static const int batchSize = 128;
  static const int historyLimit = 1024;

  static const String _activationKey = '__activation_at__';
  static const String _sequenceKey = '__sequence__';
  static const String _batchSequenceKey = '__batch_sequence__';
  static const String _pendingKey = '__pending__';
  static const String _historyKey = '__history__';
  static const String _nodePrefix = 'node:';
  static const String _groupPrefix = 'group:';

  static bool _initialized = false;
  static Future<void> _writeQueue = Future<void>.value();
  static void Function({required bool flushPartial})? _scheduler;

  static final RxInt recordsVersion = 0.obs;

  static bool get isEnabled =>
      GStorage.setting.get(
        StorageKeys.articleRelationEnabled,
        defaultValue: false,
      ) ==
      true;

  static int? get activatedAt =>
      GStorage.articleRelations.get(_activationKey) as int?;

  static int get pendingCount => _readIds(_pendingKey).length;
  static List<String> get pendingArticleIds =>
      List.unmodifiable(_readIds(_pendingKey));
  static int get historyCount => _readIds(_historyKey).length;
  static int get groupCount => GStorage.articleRelations.keys
      .whereType<String>()
      .where((key) => key.startsWith(_groupPrefix))
      .length;

  static void registerScheduler(
    void Function({required bool flushPartial}) scheduler,
  ) {
    _scheduler = scheduler;
  }

  static Future<void> initialize() async {
    if (!isEnabled) return;
    if (_initialized) return;
    _initialized = true;
    final box = GStorage.articleRelations;
    if (box.get(_activationKey) is! int) {
      await box.put(_activationKey, DateTime.now().millisecondsSinceEpoch);
      await box.put(_pendingKey, <String>[]);
      await box.put(_historyKey, <String>[]);
      recordsVersion.value++;
      return;
    }
    await recoverCompletedSummaries();
  }

  /// 摘要完成并落盘后的唯一正常入队入口。
  static Future<void> onSummaryCompleted(
    ArticleModel article,
    SummaryRecord record,
  ) async {
    if (!isEnabled) return;
    final activationWasMissing = activatedAt == null;
    await initialize();
    final summary = (record.summaryText ?? '').trim();
    final activation = activatedAt;
    if (!record.isSummarized ||
        summary.isEmpty ||
        activation == null ||
        (!activationWasMissing && record.updatedAt < activation)) {
      return;
    }
    await _enqueueNode(article, record);
  }

  /// 恢复“摘要已持久化、关系 pending 尚未来得及写入”的崩溃窗口。
  /// 只扫描启用时间之后的结构化 done 记录，旧 String 摘要不会误入队。
  static Future<void> recoverCompletedSummaries() async {
    if (!isEnabled) return;
    final activation = activatedAt;
    if (activation == null) return;
    final articles = {
      for (final article in LocalArticleDbService.readAllArticles())
        article.entryId: article,
    };
    for (final key in GStorage.summaries.keys.whereType<String>()) {
      final raw = GStorage.summaries.get(key);
      if (raw is! Map || raw['status'] != SummaryStatus.done.name) continue;
      final record = SummaryRecord.fromJson(raw.cast<dynamic, dynamic>());
      if (record.updatedAt < activation ||
          (record.summaryText ?? '').trim().isEmpty) {
        continue;
      }
      final article = articles[key];
      if (article == null) continue;
      await _enqueueNode(article, record, schedule: false);
    }
  }

  static Future<void> _enqueueNode(
    ArticleModel article,
    SummaryRecord record, {
    bool schedule = true,
  }) {
    return _serialWrite(() async {
      if (!isEnabled) return;
      final summary = record.summaryText!.trim();
      final digest = sha256.convert(utf8.encode(summary)).toString();
      final existing = nodeOf(article.entryId);
      final pending = _readIds(_pendingKey);
      if (existing?.summaryDigest == digest) {
        if (pending.contains(article.entryId) ||
            existing?.processedAt != null) {
          return;
        }
        // 修复 putAll 在进程中断时可能留下“node 已写、pending 未写”的窄窗口。
        pending.add(article.entryId);
        await GStorage.articleRelations.put(_pendingKey, pending);
        recordsVersion.value++;
        if (schedule && pending.length >= batchSize) {
          _scheduler?.call(flushPartial: false);
        }
        return;
      }

      var sequence = GStorage.articleRelations.get(_sequenceKey) as int? ?? 0;
      sequence += 1;
      final node = ArticleRelationNode(
        articleId: article.entryId,
        sequence: sequence,
        title: article.title,
        feedId: article.feedId,
        feedTitle: article.feedTitle,
        feedImage: article.feedImage,
        url: article.url,
        author: article.author,
        publishedAt: article.publishedAt,
        summary: summary,
        summaryDigest: digest,
        summaryUpdatedAt: record.updatedAt,
      );
      pending.remove(article.entryId);
      pending.add(article.entryId);
      await GStorage.articleRelations.putAll({
        _sequenceKey: sequence,
        '$_nodePrefix${article.entryId}': node.toJson(),
        _pendingKey: pending,
      });
      recordsVersion.value++;
      if (schedule && pending.length >= batchSize) {
        _scheduler?.call(flushPartial: false);
      }
    });
  }

  static ArticleRelationNode? nodeOf(String articleId) {
    final raw = GStorage.articleRelations.get('$_nodePrefix$articleId');
    if (raw is! Map) return null;
    return ArticleRelationNode.fromJson(raw.cast<dynamic, dynamic>());
  }

  static Future<ArticleRelationBatchInput?> prepareNextBatch({
    required bool flushPartial,
  }) {
    return _serialWrite(() async {
      if (!isEnabled) return null;
      final pending = _readIds(_pendingKey);
      if (pending.isEmpty || (!flushPartial && pending.length < batchSize)) {
        return null;
      }
      final newIds = pending.take(batchSize).toList(growable: false);
      final newIdSet = newIds.toSet();
      final newNodes = newIds
          .map(nodeOf)
          .whereType<ArticleRelationNode>()
          .toList(growable: false);
      if (newNodes.isEmpty) return null;

      final historyNodes = _readIds(_historyKey)
          .where((id) => !newIdSet.contains(id))
          .map(nodeOf)
          .whereType<ArticleRelationNode>()
          .toList(growable: false);
      var batchSequence =
          GStorage.articleRelations.get(_batchSequenceKey) as int? ?? 0;
      batchSequence += 1;
      await GStorage.articleRelations.put(_batchSequenceKey, batchSequence);
      return ArticleRelationBatchInput(
        id: 'relation-${batchSequence.toString().padLeft(6, '0')}',
        newNodes: newNodes,
        historyNodes: historyNodes,
      );
    });
  }

  static Future<bool> completeBatch(
    ArticleRelationBatchInput input,
    List<ArticleRelationCandidateGroup> groups,
  ) {
    return _serialWrite(() async {
      // 开关可能在网络响应返回与串行写入之间关闭，最终提交必须再次核对。
      if (!isEnabled) return false;
      final now = DateTime.now().millisecondsSinceEpoch;
      final newIds = input.newNodes.map((node) => node.articleId).toSet();
      final pending = _readIds(_pendingKey)..removeWhere(newIds.contains);
      final history = _readIds(_historyKey)
        ..removeWhere(newIds.contains)
        ..addAll(input.newNodes.map((node) => node.articleId));
      while (history.length > historyLimit) {
        final evictionCount = batchSize.clamp(0, history.length);
        history.removeRange(0, evictionCount);
      }

      final existingGroups = <String, ArticleRelationGroup>{};
      final staleGroupKeys = <String>{};
      for (final key in GStorage.articleRelations.keys.whereType<String>()) {
        if (!key.startsWith(_groupPrefix)) continue;
        final raw = GStorage.articleRelations.get(key);
        if (raw is! Map) continue;
        final old = ArticleRelationGroup.fromJson(raw.cast<dynamic, dynamic>());
        existingGroups[key] = old;
        if (old.memberIds.any(newIds.contains)) staleGroupKeys.add(key);
      }

      final updates = <dynamic, dynamic>{
        _pendingKey: pending,
        _historyKey: history,
      };
      for (final node in input.newNodes) {
        updates['$_nodePrefix${node.articleId}'] = node
            .copyWith(processedAt: now, lastBatchId: input.id)
            .toJson();
      }
      final newRecords = <ArticleRelationGroup>[];
      for (var i = 0; i < groups.length; i++) {
        final group = groups[i];
        final memberIds = group.memberIds.toSet();
        if (group.kind == ArticleRelationKind.sameEvent) {
          var merged = true;
          while (merged) {
            merged = false;
            for (final entry in existingGroups.entries) {
              if (staleGroupKeys.contains(entry.key) ||
                  entry.value.kind != ArticleRelationKind.sameEvent ||
                  !entry.value.memberIds.any(memberIds.contains)) {
                continue;
              }
              memberIds.addAll(entry.value.memberIds);
              staleGroupKeys.add(entry.key);
              merged = true;
            }
            for (var index = newRecords.length - 1; index >= 0; index--) {
              final existing = newRecords[index];
              if (existing.kind != ArticleRelationKind.sameEvent ||
                  !existing.memberIds.any(memberIds.contains)) {
                continue;
              }
              memberIds.addAll(existing.memberIds);
              newRecords.removeAt(index);
              merged = true;
            }
          }
        }
        final record = ArticleRelationGroup(
          id: '${input.id}-g${i + 1}',
          batchId: input.id,
          memberIds: memberIds.toList(growable: false),
          reason: group.reason,
          confidence: group.confidence,
          createdAt: now,
          kind: group.kind,
        );
        newRecords.add(record);
      }
      if (staleGroupKeys.isNotEmpty) {
        await GStorage.articleRelations.deleteAll(staleGroupKeys.toList());
      }
      for (final record in newRecords) {
        updates['$_groupPrefix${record.id}'] = record.toJson();
      }
      await GStorage.articleRelations.putAll(updates);
      recordsVersion.value++;
      return true;
    });
  }

  static List<ArticleRelationGroup> groupsFor(String articleId) {
    final result = <ArticleRelationGroup>[];
    for (final key in GStorage.articleRelations.keys.whereType<String>()) {
      if (!key.startsWith(_groupPrefix)) continue;
      final raw = GStorage.articleRelations.get(key);
      if (raw is! Map) continue;
      final group = ArticleRelationGroup.fromJson(raw.cast<dynamic, dynamic>());
      if (group.enabled && group.memberIds.contains(articleId)) {
        result.add(group);
      }
    }
    return result;
  }

  static List<ArticleRelationDisplayItem> directRelationsFor(String articleId) {
    final kindsById = <String, ArticleRelationKind>{};
    for (final group in groupsFor(articleId)) {
      for (final id in group.memberIds.where((id) => id != articleId)) {
        final current = kindsById[id];
        if (current == null || group.kind == ArticleRelationKind.equivalent) {
          kindsById[id] = group.kind;
        }
      }
    }
    return _displayItems(kindsById);
  }

  static List<ArticleRelationDisplayItem> componentFor(String articleId) {
    final kindsById = <String, ArticleRelationKind>{
      articleId: ArticleRelationKind.equivalent,
    };
    final queue = <String>[articleId];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final currentKind = kindsById[current]!;
      for (final group in groupsFor(current)) {
        for (final id in group.memberIds) {
          final nextKind =
              currentKind == ArticleRelationKind.equivalent &&
                  group.kind == ArticleRelationKind.equivalent
              ? ArticleRelationKind.equivalent
              : ArticleRelationKind.sameEvent;
          final previous = kindsById[id];
          if (previous == null ||
              (previous == ArticleRelationKind.sameEvent &&
                  nextKind == ArticleRelationKind.equivalent)) {
            kindsById[id] = nextKind;
            if (id != current) queue.add(id);
          }
        }
      }
    }
    kindsById.remove(articleId);
    return _displayItems(kindsById);
  }

  static bool hasSameEventGroup(String articleId) => groupsFor(
    articleId,
  ).any((group) => group.kind == ArticleRelationKind.sameEvent);

  static List<ArticleRelationDisplayItem> _displayItems(
    Map<String, ArticleRelationKind> kindsById,
  ) {
    final articles = {
      for (final article in LocalArticleDbService.readAllArticles())
        article.entryId: article,
    };
    final items = kindsById.entries
        .map((entry) {
          final id = entry.key;
          final node = nodeOf(id);
          return node == null
              ? null
              : ArticleRelationDisplayItem(
                  node: node,
                  kind: entry.value,
                  article: articles[id],
                );
        })
        .whereType<ArticleRelationDisplayItem>()
        .toList();
    items.sort((a, b) => b.node.sequence.compareTo(a.node.sequence));
    return items;
  }

  static void notifySummaryQueueIdle() {
    if (isEnabled && pendingCount > 0) {
      _scheduler?.call(flushPartial: true);
    }
  }

  /// 开启时以当前时刻作为新边界，不追溯关闭期间完成的摘要。
  static Future<void> activateFromNow() {
    return _serialWrite(() async {
      final box = GStorage.articleRelations;
      await box.put(_activationKey, DateTime.now().millisecondsSinceEpoch);
      if (box.get(_pendingKey) is! List) {
        await box.put(_pendingKey, <String>[]);
      }
      if (box.get(_historyKey) is! List) {
        await box.put(_historyKey, <String>[]);
      }
      _initialized = true;
      recordsVersion.value++;
    });
  }

  /// 关闭时丢弃未完成的派生节点，不形成待补算积压。
  static Future<void> discardPending() {
    return _serialWrite(() async {
      final pending = _readIds(_pendingKey);
      if (pending.isEmpty) return;
      await GStorage.articleRelations.deleteAll([
        for (final articleId in pending) '$_nodePrefix$articleId',
      ]);
      await GStorage.articleRelations.put(_pendingKey, <String>[]);
      recordsVersion.value++;
    });
  }

  static void resetForAccountChange() {
    _initialized = false;
    _writeQueue = Future<void>.value();
    recordsVersion.value++;
  }

  @visibleForTesting
  static Future<void> resetForTest({int? activatedAt}) async {
    await GStorage.articleRelations.clear();
    await GStorage.relationBatches.clear();
    _initialized = false;
    _writeQueue = Future<void>.value();
    _scheduler = null;
    await GStorage.setting.put(StorageKeys.articleRelationEnabled, true);
    if (activatedAt != null) {
      await GStorage.articleRelations.put(_activationKey, activatedAt);
    }
    await initialize();
  }

  static List<String> _readIds(String key) {
    final raw = GStorage.articleRelations.get(key);
    return (raw as List<dynamic>? ?? const []).whereType<String>().toList(
      growable: true,
    );
  }

  static Future<T> _serialWrite<T>(Future<T> Function() write) {
    final operation = _writeQueue.then((_) => write());
    _writeQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }
}
