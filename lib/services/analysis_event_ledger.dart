import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/article.dart';
import '../utils/storage.dart';

enum ReadStateChangeSource { user, syncInference }

enum RemoteReadRequestSource {
  articleController,
  singleAction,
  batchAction,
  pendingQueue,
}

/// 本地分析事件账本 — 版本化、追加式、账号级。
///
/// 作为未来统计中心和 JSON 导出的唯一数据来源。从本版本开始记录，
/// 不伪造历史事件；退出或切换账号时随账号数据一起清理。
///
/// 记录范围（写入集中在操作服务中，不在页面重复拼装）：
/// - AI 分类结果、理由和时间（[recordAiClassification]）
/// - 用户 M/K/N 等人工操作及操作前后状态（[recordUserAction]）
/// - 标为已读 / 恢复未读（[recordReadStateChange]）
/// - 文章打开事件（[recordArticleOpen]）
/// - 实际发往 Folo 的已读请求及结果（[recordRemoteMarkReadAttempt]）
///
/// 语义约定：
/// - K 表示「保留或稍后确认」，不能自动解释为 AI 分类错误。
/// - N 将漏网文章移入垃圾拦截（n_spam），才可作为明确纠正信号。
///
/// 不保存正文、摘要、翻译、Prompt、API key、Session Token。
/// 暂不限制事件数量，暂不提供统计中心和导出 UI。
abstract final class AnalysisEventLedger {
  /// 账本 schema 版本。未来格式变更时在此递增并提供迁移。
  static const int schemaVersion = 1;

  static const String _versionKey = '__version__';
  static const String _seqKey = '__seq__';
  static const int _keyWidth = 12;

  static bool _versionChecked = false;

  /// 追加一条事件。返回事件的序号（用于调试与测试）。
  static int record({
    required String type,
    ArticleModel? article,
    String? entryId,
    String? feedId,
    String? feedTitle,
    String? title,
    Map<String, Object?>? data,
  }) {
    final box = GStorage.analysisEvents;
    _checkVersion(box);
    var seq = box.get(_seqKey) as int? ?? 0;
    seq += 1;
    final event = <String, dynamic>{
      'type': type,
      'ts': DateTime.now().millisecondsSinceEpoch,
      ..._articleFieldsOrEmpty(article),
      'articleId': ?entryId,
      'feedId': ?feedId,
      'feedTitle': ?feedTitle,
      'title': ?title,
      if (data != null && data.isNotEmpty) 'data': data,
    };
    unawaited(box.put(_keyFor(seq), event));
    unawaited(box.put(_seqKey, seq));
    return seq;
  }

  /// AI 分类结果：判定拒绝（移入垃圾拦截）或判定保留。
  static void recordAiClassification({
    required ArticleModel article,
    required bool shouldReject,
    String? reason,
    required Map<String, Object?> after,
  }) {
    record(
      type: 'ai_classified',
      article: article,
      data: {
        'shouldReject': shouldReject,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
        'after': after,
      },
    );
  }

  /// 用户人工操作（M / K / N 等），action 使用 [ArticleModel] 的
  /// userAction 常量语义：k / m / n_keep / n_spam。
  static void recordUserAction({
    required ArticleModel article,
    required String action,
    required Map<String, Object?> before,
    required Map<String, Object?> after,
  }) {
    record(
      type: 'user_action',
      article: article,
      data: {'action': action, 'before': before, 'after': after},
    );
  }

  /// 标为已读 / 恢复未读。
  static void recordReadStateChange({
    required String entryId,
    required bool isRead,
    required ArticleModel before,
    required ReadStateChangeSource source,
  }) {
    record(
      type: isRead ? 'mark_read' : 'mark_unread',
      article: before,
      data: {
        'source': source.name,
        'after': {'isRead': isRead},
      },
    );
  }

  /// 文章打开事件（进入阅读视图，不含相邻预构建页）。
  static void recordArticleOpen(ArticleModel article) {
    record(type: 'article_open', article: article);
  }

  /// 记录一次真正发往 Folo 的标已读请求。
  ///
  /// 返回事件序号用于和结果事件关联。审计是尽力写入：账本不可用时
  /// 返回 null，绝不能阻断用户的已读同步。
  static int? recordRemoteMarkReadAttempt({
    required List<String> entryIds,
    required bool isInbox,
    required RemoteReadRequestSource source,
    Map<String, int>? queuedAtByEntryId,
  }) {
    try {
      final ids = entryIds
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
      return record(
        type: 'remote_mark_read_attempt',
        entryId: ids.length == 1 ? ids.single : null,
        data: {
          'source': source.name,
          'entryIds': ids,
          'isInbox': isInbox,
          if (queuedAtByEntryId != null && queuedAtByEntryId.isNotEmpty)
            'queuedAtByEntryId': queuedAtByEntryId,
        },
      );
    } catch (error) {
      debugPrint('[AnalysisLedger] remote mark-read attempt skipped: $error');
      return null;
    }
  }

  /// 记录对应远端标已读请求的最终结果。
  static void recordRemoteMarkReadResult({
    required int? attemptSequence,
    required List<String> entryIds,
    required RemoteReadRequestSource source,
    required bool success,
    required int durationMs,
    int? statusCode,
    String? failureKind,
  }) {
    try {
      final ids = entryIds
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
      record(
        type: 'remote_mark_read_result',
        entryId: ids.length == 1 ? ids.single : null,
        data: {
          'source': source.name,
          'entryIds': ids,
          'attemptSequence': ?attemptSequence,
          'success': success,
          'durationMs': durationMs,
          'statusCode': ?statusCode,
          'failureKind': ?failureKind,
        },
      );
    } catch (error) {
      debugPrint('[AnalysisLedger] remote mark-read result skipped: $error');
    }
  }

  /// 文章分类状态快照（不包含正文/摘要/翻译等敏感内容）。
  static Map<String, Object?> stateSnapshotOf(ArticleModel article) {
    return {
      'isRead': article.isRead,
      'isRejectedByAi': article.isRejectedByAi,
      'filterReviewed': article.filterReviewed,
      if (article.userAction != null) 'userAction': article.userAction,
      if (article.filterReason != null && article.filterReason!.isNotEmpty)
        'filterReason': article.filterReason,
      if (article.filteredAt != null) 'filteredAt': article.filteredAt,
    };
  }

  /// 当前事件总数（测试与诊断用）。
  static int get count {
    final box = GStorage.analysisEvents;
    return box.get(_seqKey) as int? ?? 0;
  }

  /// 清空账本（账号退出 / 切换时调用）。
  static Future<void> clear() async {
    final box = GStorage.analysisEvents;
    for (final key in box.keys.toList()) {
      await box.delete(key);
    }
    _versionChecked = false;
  }

  static Map<String, Object?> _articleFields(ArticleModel article) {
    return {
      'articleId': article.entryId,
      if (article.feedId.isNotEmpty) 'feedId': article.feedId,
      if (article.feedTitle.isNotEmpty && article.feedTitle != '?')
        'feedTitle': article.feedTitle,
      if (article.title.isNotEmpty && article.title != '?')
        'title': article.title,
    };
  }

  static Map<String, Object?> _articleFieldsOrEmpty(ArticleModel? article) {
    return article == null ? const {} : _articleFields(article);
  }

  static String _keyFor(int seq) {
    return seq.toString().padLeft(_keyWidth, '0');
  }

  static void _checkVersion(Box<dynamic> box) {
    if (_versionChecked) return;
    _versionChecked = true;
    final raw = box.get(_versionKey);
    if (raw is! int) {
      unawaited(box.put(_versionKey, schemaVersion));
      return;
    }
    if (raw != schemaVersion) {
      debugPrint('[AnalysisLedger] schema $raw → $schemaVersion; 迁移逻辑待实现');
      unawaited(box.put(_versionKey, schemaVersion));
    }
  }
}
