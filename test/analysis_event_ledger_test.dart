import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/models/article.dart';
import 'package:fourier/services/analysis_event_ledger.dart';
import 'package:fourier/services/local_article_db_service.dart';
import 'package:fourier/utils/storage.dart';

import 'support/hive_test_helper.dart';

ArticleModel _article() {
  return ArticleModel(
    entryId: 'entry-1',
    feedId: 'feed-1',
    feedTitle: '测试源',
    title: '文章标题',
    url: 'https://example.com/1',
    content: '<p>正文（账本不得保存）</p>',
    isRead: false,
  );
}

void main() {
  setUp(HiveTestHelper.setUp);
  tearDown(HiveTestHelper.tearDown);

  test('记录 AI 分类结果、理由与时间', () async {
    final article = _article();
    AnalysisEventLedger.recordAiClassification(
      article: article,
      shouldReject: true,
      reason: '与主题无关',
      after: AnalysisEventLedger.stateSnapshotOf(article),
    );

    final raw = GStorage.analysisEvents.get('000000000001');
    expect(raw, isA<Map>());
    final event = Map<String, dynamic>.from(raw as Map);
    expect(event['type'], 'ai_classified');
    expect(event['articleId'], 'entry-1');
    expect(event['feedId'], 'feed-1');
    expect(event['feedTitle'], '测试源');
    expect(event['title'], '文章标题');
    expect(event['ts'], isA<int>());
    final data = Map<String, dynamic>.from(event['data'] as Map);
    expect(data['shouldReject'], isTrue);
    expect(data['reason'], '与主题无关');
    // 不保存正文。
    expect(event.containsKey('content'), isFalse);
    expect(event.toString().contains('正文（账本不得保存）'), isFalse);
  });

  test('记录用户 M/K/N 操作及操作前后状态', () async {
    final article = _article();
    AnalysisEventLedger.recordUserAction(
      article: article,
      action: ArticleModel.userActionMisclassifySpam,
      before: AnalysisEventLedger.stateSnapshotOf(article),
      after: {
        ...AnalysisEventLedger.stateSnapshotOf(article),
        'isRead': true,
        'isRejectedByAi': true,
      },
    );

    final raw = GStorage.analysisEvents.get('000000000001');
    final event = Map<String, dynamic>.from(raw as Map);
    expect(event['type'], 'user_action');
    final data = Map<String, dynamic>.from(event['data'] as Map);
    expect(data['action'], 'n_spam');
    final before = Map<String, dynamic>.from(data['before'] as Map);
    final after = Map<String, dynamic>.from(data['after'] as Map);
    expect(before['isRead'], isFalse);
    expect(after['isRead'], isTrue);
    expect(after['isRejectedByAi'], isTrue);
  });

  test('记录标为已读与恢复未读', () async {
    final article = _article();
    AnalysisEventLedger.recordReadStateChange(
      entryId: article.entryId,
      isRead: true,
      before: article,
      source: ReadStateChangeSource.user,
    );
    AnalysisEventLedger.recordReadStateChange(
      entryId: article.entryId,
      isRead: false,
      before: article,
      source: ReadStateChangeSource.syncInference,
    );

    final first = Map<String, dynamic>.from(
      GStorage.analysisEvents.get('000000000001') as Map,
    );
    final second = Map<String, dynamic>.from(
      GStorage.analysisEvents.get('000000000002') as Map,
    );
    expect(first['type'], 'mark_read');
    expect(second['type'], 'mark_unread');
    expect((first['data'] as Map)['source'], 'user');
    expect((second['data'] as Map)['source'], 'syncInference');
  });

  test('记录文章打开事件', () async {
    AnalysisEventLedger.recordArticleOpen(_article());
    final raw = GStorage.analysisEvents.get('000000000001');
    final event = Map<String, dynamic>.from(raw as Map);
    expect(event['type'], 'article_open');
    expect(event['articleId'], 'entry-1');
  });

  test('记录远端标已读请求并关联成功结果', () {
    final attemptSequence = AnalysisEventLedger.recordRemoteMarkReadAttempt(
      entryIds: const ['entry-1'],
      isInbox: true,
      source: RemoteReadRequestSource.pendingQueue,
      queuedAtByEntryId: const {'entry-1': 123456789},
    );
    AnalysisEventLedger.recordRemoteMarkReadResult(
      attemptSequence: attemptSequence,
      entryIds: const ['entry-1'],
      source: RemoteReadRequestSource.pendingQueue,
      success: true,
      durationMs: 42,
      statusCode: 200,
    );

    final attempt = Map<String, dynamic>.from(
      GStorage.analysisEvents.get('000000000001') as Map,
    );
    final attemptData = Map<String, dynamic>.from(attempt['data'] as Map);
    expect(attempt['type'], 'remote_mark_read_attempt');
    expect(attempt['articleId'], 'entry-1');
    expect(attemptData['source'], 'pendingQueue');
    expect(attemptData['entryIds'], ['entry-1']);
    expect(attemptData['isInbox'], isTrue);
    expect(Map<String, dynamic>.from(attemptData['queuedAtByEntryId'] as Map), {
      'entry-1': 123456789,
    });

    final result = Map<String, dynamic>.from(
      GStorage.analysisEvents.get('000000000002') as Map,
    );
    final resultData = Map<String, dynamic>.from(result['data'] as Map);
    expect(result['type'], 'remote_mark_read_result');
    expect(result['articleId'], 'entry-1');
    expect(resultData['attemptSequence'], attemptSequence);
    expect(resultData['success'], isTrue);
    expect(resultData['durationMs'], 42);
    expect(resultData['statusCode'], 200);
  });

  test('批量远端标已读失败保留来源和失败类型', () {
    final attemptSequence = AnalysisEventLedger.recordRemoteMarkReadAttempt(
      entryIds: const ['entry-1', 'entry-2'],
      isInbox: false,
      source: RemoteReadRequestSource.batchAction,
    );
    AnalysisEventLedger.recordRemoteMarkReadResult(
      attemptSequence: attemptSequence,
      entryIds: const ['entry-1', 'entry-2'],
      source: RemoteReadRequestSource.batchAction,
      success: false,
      durationMs: 300,
      statusCode: 503,
      failureKind: 'http_status',
    );

    final attempt = Map<String, dynamic>.from(
      GStorage.analysisEvents.get('000000000001') as Map,
    );
    expect(attempt.containsKey('articleId'), isFalse);

    final result = Map<String, dynamic>.from(
      GStorage.analysisEvents.get('000000000002') as Map,
    );
    final data = Map<String, dynamic>.from(result['data'] as Map);
    expect(data['source'], 'batchAction');
    expect(data['entryIds'], ['entry-1', 'entry-2']);
    expect(data['success'], isFalse);
    expect(data['statusCode'], 503);
    expect(data['failureKind'], 'http_status');
  });

  test('只记录真实读状态变化并保留来源', () {
    final article = _article();
    LocalArticleDbService.upsertOne(article);

    LocalArticleDbService.setReadState(article.entryId, false);
    expect(AnalysisEventLedger.count, 0);

    LocalArticleDbService.setReadState(
      article.entryId,
      true,
      source: ReadStateChangeSource.syncInference,
    );
    expect(AnalysisEventLedger.count, 1);
    final event = Map<String, dynamic>.from(
      GStorage.analysisEvents.get('000000000001') as Map,
    );
    expect((event['data'] as Map)['source'], 'syncInference');

    LocalArticleDbService.setReadState(article.entryId, true);
    expect(AnalysisEventLedger.count, 1);
  });

  test('事件追加式编号递增，清空后从新版本开始', () async {
    AnalysisEventLedger.recordArticleOpen(_article());
    AnalysisEventLedger.recordArticleOpen(_article());
    expect(AnalysisEventLedger.count, 2);

    await AnalysisEventLedger.clear();
    expect(AnalysisEventLedger.count, 0);
    expect(GStorage.analysisEvents.keys, isEmpty);

    AnalysisEventLedger.recordArticleOpen(_article());
    final raw = GStorage.analysisEvents.get('000000000001');
    expect(raw, isA<Map>());
    expect(AnalysisEventLedger.count, 1);
  });

  test('状态快照不包含正文/摘要等敏感内容', () {
    final snapshot = AnalysisEventLedger.stateSnapshotOf(_article());
    expect(snapshot.keys, isNot(contains('content')));
    expect(snapshot.keys, isNot(contains('summary')));
    expect(snapshot['isRead'], isFalse);
    expect(snapshot['isRejectedByAi'], isFalse);
  });
}
