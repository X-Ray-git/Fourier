import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/models/article.dart';
import 'package:fourier/services/analysis_event_ledger.dart';
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
    );
    AnalysisEventLedger.recordReadStateChange(
      entryId: article.entryId,
      isRead: false,
      before: article,
    );

    final first = Map<String, dynamic>.from(
      GStorage.analysisEvents.get('000000000001') as Map,
    );
    final second = Map<String, dynamic>.from(
      GStorage.analysisEvents.get('000000000002') as Map,
    );
    expect(first['type'], 'mark_read');
    expect(second['type'], 'mark_unread');
  });

  test('记录文章打开事件', () async {
    AnalysisEventLedger.recordArticleOpen(_article());
    final raw = GStorage.analysisEvents.get('000000000001');
    final event = Map<String, dynamic>.from(raw as Map);
    expect(event['type'], 'article_open');
    expect(event['articleId'], 'entry-1');
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
