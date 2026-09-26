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
    this.relationGroups = const [],
    this.epoch = 0,
  });

  final String id;
  final List<ArticleRelationNode> newNodes;
  final List<ArticleRelationNode> historyNodes;
  final List<ArticleRelationGroup> relationGroups;
  final int epoch;
}

class ArticleRelationCandidateGroup {
  const ArticleRelationCandidateGroup({
    required this.kind,
    required this.memberIds,
    required this.reason,
    required this.confidence,
    this.groupId,
    this.topic = '',
  });

  final ArticleRelationKind kind;
  final List<String> memberIds;
  final String reason;
  final double confidence;
  final String? groupId;
  final String topic;
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
  static const int schemaVersion = 5;
  static const int batchSize = 128;
  static const int historyLimit = 2048;
  static const int historyEvictionSize = 1024;

  static const String _schemaKey = '__schema_version__';
  static int _epoch = 0;
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

  static int get previewCount {
    final value = GStorage.setting.get(StorageKeys.relatedArticlesPreviewCount);
    return value is int && value >= 1
        ? value
        : AppConstants.defaultRelatedArticlesPreviewCount;
  }

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
    await migrateToSingleKind();
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

  /// v5 preserves every historical group and queue entry. Only the kind changes;
  /// write the schema marker last so an interrupted conversion can safely resume.
  static Future<void> migrateToSingleKind() => _serialWrite(() async {
    final box = GStorage.articleRelations;
    if (box.get(_schemaKey) == schemaVersion) return;
    _epoch++;
    for (final key in box.keys.whereType<String>().toList()) {
      if (!key.startsWith(_groupPrefix)) continue;
      final raw = box.get(key);
      if (raw is! Map) continue;
      await box.put(key, {...raw, 'kind': 'equivalent'});
    }
    await box.put(_schemaKey, schemaVersion);
    recordsVersion.value++;
  });

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
    await _enqueueNode(article, record, allowInitial: activationWasMissing);
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
    bool allowInitial = false,
  }) {
    return _serialWrite(() async {
      if (!isEnabled ||
          (!allowInitial && record.updatedAt < (activatedAt ?? 0))) {
        return;
      }
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
        epoch: _epoch,
        relationGroups: allGroups(),
      );
    });
  }

  static Future<bool> completeBatch(
    ArticleRelationBatchInput input,
    List<ArticleRelationCandidateGroup> groups,
  ) {
    return _serialWrite(() async {
      // 开关可能在网络响应返回与串行写入之间关闭，最终提交必须再次核对。
      if (!isEnabled || input.epoch != _epoch) return false;
      final now = DateTime.now().millisecondsSinceEpoch;
      final newIds = input.newNodes.map((node) => node.articleId).toSet();
      final pending = _readIds(_pendingKey)..removeWhere(newIds.contains);
      final history = _readIds(_historyKey)
        ..removeWhere(newIds.contains)
        ..addAll(input.newNodes.map((node) => node.articleId));
      while (history.length > historyLimit) {
        final evictionCount = historyEvictionSize.clamp(0, history.length);
        history.removeRange(0, evictionCount);
      }

      final existing = {for (final g in allGroups()) g.id: g};
      // Historical groups may overlap. Preserve all memberships, but never use
      // a new operation to merge groups or transfer one group's members.
      final owners = <String, Set<String>>{};
      for (final group in existing.values) {
        for (final member in group.memberIds) {
          (owners[member] ??= <String>{}).add(group.id);
        }
      }
      final allowedIds = {
        ...input.newNodes,
        ...input.historyNodes,
      }.map((n) => n.articleId).toSet();
      final updates = <dynamic, dynamic>{
        _pendingKey: pending,
        _historyKey: history,
      };
      for (final node in input.newNodes) {
        updates['$_nodePrefix${node.articleId}'] = node
            .copyWith(processedAt: now, lastBatchId: input.id)
            .toJson();
      }
      for (var i = 0; i < groups.length; i++) {
        final candidate = groups[i];
        final members = candidate.memberIds.toSet();
        if (!members.every(allowedIds.contains) ||
            !members.any(newIds.contains)) {
          continue;
        }
        final joining = candidate.groupId != null;
        final old = joining ? existing[candidate.groupId] : null;
        if (joining &&
            (old == null || !input.relationGroups.any((g) => g.id == old.id))) {
          continue;
        }
        if (members.length < (joining ? 1 : 2)) continue;
        final id = old?.id ?? '${input.id}-g${i + 1}';
        if (members.any(
          (member) =>
              (owners[member] ?? const <String>{}).any((owner) => owner != id),
        )) {
          continue;
        }
        final topic = candidate.topic.trim().isEmpty
            ? old?.topic.trim() ?? ''
            : candidate.topic.trim();
        if (topic.isEmpty || topic == '暂无关系概述') {
          throw const FormatException('关系缺少一句话概述');
        }
        for (final member in members) {
          (owners[member] ??= <String>{}).add(id);
        }
        final topicHistory = [...?old?.topicHistory];
        if (old != null && old.topic != topic) topicHistory.add(old.topic);
        final record = ArticleRelationGroup(
          id: id,
          batchId: input.id,
          memberIds: {...?old?.memberIds, ...members}.toList(),
          reason: candidate.reason,
          confidence: candidate.confidence,
          createdAt: old?.createdAt ?? now,
          kind: candidate.kind,
          topic: topic,
          topicHistory: topicHistory,
        );
        existing[id] = record;
        updates['$_groupPrefix$id'] = record.toJson();
      }
      await GStorage.articleRelations.putAll(updates);
      recordsVersion.value++;
      return true;
    });
  }

  static List<ArticleRelationGroup> allGroups() => [
    for (final key in GStorage.articleRelations.keys.whereType<String>())
      if (key.startsWith(_groupPrefix) &&
          GStorage.articleRelations.get(key) is Map)
        ArticleRelationGroup.fromJson(
          GStorage.articleRelations.get(key) as Map,
        ),
  ].where((g) => g.enabled).toList();

  static List<ArticleRelationGroup> groupsFor(String articleId) =>
      allGroups().where((g) => g.memberIds.contains(articleId)).toList();

  static List<ArticleRelationDisplayItem> directRelationsFor(String articleId) {
    final kindsById = <String, ArticleRelationKind>{};
    for (final group in groupsFor(articleId)) {
      for (final id in group.memberIds.where((id) => id != articleId)) {
        kindsById[id] = group.kind;
      }
    }
    return _displayItems(kindsById);
  }

  // Kept as an API alias: relations never expand through another article.
  static List<ArticleRelationDisplayItem> componentFor(String articleId) =>
      directRelationsFor(articleId);

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
    _epoch++;
    _initialized = false;
    _writeQueue = Future<void>.value();
    recordsVersion.value++;
  }

  @visibleForTesting
  static Future<void> resetForTest({int? activatedAt}) async {
    await GStorage.articleRelations.clear();
    await GStorage.relationBatches.clear();
    _epoch = 0;
    await GStorage.articleRelations.put(_schemaKey, schemaVersion);
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
