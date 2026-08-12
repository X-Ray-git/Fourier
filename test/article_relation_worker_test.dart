import 'package:flutter_test/flutter_test.dart';

import 'package:fourier/models/article.dart';
import 'package:fourier/models/article_relation.dart';
import 'package:fourier/services/article_relation_service.dart';
import 'package:fourier/services/article_relation_worker.dart';
import 'package:fourier/services/summary_service.dart';
import 'package:fourier/utils/storage.dart';

import 'support/hive_test_helper.dart';

void main() {
  setUp(() async {
    await HiveTestHelper.setUp();
    ArticleRelationWorker.resetForTest();
  });
  tearDown(() async {
    ArticleRelationWorker.resetForTest();
    await HiveTestHelper.tearDown();
  });

  test('解析有效关系并忽略不含新文章的关系组', () {
    final labels = {
      'N001': _node('new-1'),
      'H001': _node('history-1'),
      'H002': _node('history-2'),
    };
    final result = ArticleRelationWorker.parseResponse({
      'choices': [
        {
          'finish_reason': 'stop',
          'message': {
            'content':
                '{"groups":['
                '{"type":"same_event","members":["N001","H001"],"reason":"同一发布","confidence":0.91},'
                '{"type":"equivalent","members":["N001","H002"],"reason":"近似重复","confidence":0.95},'
                '{"type":"equivalent","members":["H001","H002"],"reason":"历史内部","confidence":0.8},'
                '{"type":"unknown","members":["N001","H002"],"reason":"未知类型","confidence":0.8}'
                ']}',
          },
        },
      ],
      'usage': {
        'prompt_tokens': 100,
        'completion_tokens': 20,
        'prompt_cache_hit_tokens': 80,
        'prompt_cache_miss_tokens': 20,
        'total_tokens': 120,
      },
    }, labels);

    expect(result.groups, hasLength(2));
    expect(result.groups.first.kind, ArticleRelationKind.sameEvent);
    expect(result.groups.first.memberIds, ['new-1', 'history-1']);
    expect(result.groups.first.confidence, 0.91);
    expect(result.groups.last.kind, ArticleRelationKind.equivalent);
    expect(result.groups.last.memberIds, ['new-1', 'history-2']);
    expect(result.cacheHitTokens, 80);
    expect(result.cacheMissTokens, 20);
    expect(result.totalTokens, 120);
  });

  test('旧版无类型关系输出兼容为近似重复', () {
    final result = ArticleRelationWorker.parseResponse(
      {
        'choices': [
          {
            'finish_reason': 'stop',
            'message': {
              'content':
                  '{"groups":[{"members":["N001","H001"],"reason":"旧输出","confidence":0.8}]}',
            },
          },
        ],
      },
      {'N001': _node('new-1'), 'H001': _node('history-1')},
    );

    expect(result.groups, hasLength(1));
    expect(result.groups.single.kind, ArticleRelationKind.equivalent);
  });

  test('截断响应不能被当成成功批次', () {
    expect(
      () => ArticleRelationWorker.parseResponse(
        {
          'choices': [
            {
              'finish_reason': 'length',
              'message': {'content': '{"groups":[]}'},
            },
          ],
        },
        {'N001': _node('new-1')},
      ),
      throwsFormatException,
    );
  });

  test('关闭会丢弃待处理队列，重新开启不追溯关闭期间摘要', () async {
    await ArticleRelationService.resetForTest(activatedAt: 1);
    await ArticleRelationWorker.initialize();
    await ArticleRelationService.onSummaryCompleted(
      _article('queued'),
      const SummaryRecord(
        status: SummaryStatus.done,
        summaryText: '等待处理',
        updatedAt: 1000,
      ),
    );
    expect(ArticleRelationService.pendingCount, 1);

    await ArticleRelationWorker.setEnabled(false);
    expect(ArticleRelationService.isEnabled, isFalse);
    expect(ArticleRelationService.pendingCount, 0);
    expect(ArticleRelationService.nodeOf('queued'), isNull);

    await ArticleRelationService.onSummaryCompleted(
      _article('while-off'),
      const SummaryRecord(
        status: SummaryStatus.done,
        summaryText: '关闭期间完成',
        updatedAt: 2000,
      ),
    );
    await ArticleRelationWorker.setEnabled(true);
    expect(ArticleRelationService.nodeOf('while-off'), isNull);

    await ArticleRelationService.onSummaryCompleted(
      _article('after-on'),
      SummaryRecord(
        status: SummaryStatus.done,
        summaryText: '开启后完成',
        updatedAt: DateTime.now().millisecondsSinceEpoch + 1,
      ),
    );
    expect(ArticleRelationService.pendingArticleIds, ['after-on']);
  });

  test('冷启动不冲刷尾批，摘要队列空闲后立即处理', () async {
    await ArticleRelationService.resetForTest(activatedAt: 1);
    await ArticleRelationService.onSummaryCompleted(
      _article('new-1'),
      const SummaryRecord(
        status: SummaryStatus.done,
        summaryText: '摘要',
        updatedAt: 1000,
      ),
    );
    var requestCount = 0;
    ArticleRelationWorker.debugRequestOverride = (input) async {
      requestCount++;
      return const ArticleRelationApiResult(groups: []);
    };

    await ArticleRelationWorker.initialize();
    await _waitForMicrotasks();
    expect(requestCount, 0);
    expect(ArticleRelationService.pendingCount, 1);

    ArticleRelationService.notifySummaryQueueIdle();
    await _waitUntil(() => ArticleRelationService.pendingCount == 0);
    expect(requestCount, 1);
    expect(ArticleRelationService.historyCount, 1);
  });

  test('冷启动恢复失败状态后，空闲通知不能绕过手动重试', () async {
    await ArticleRelationService.resetForTest(activatedAt: 1);
    await ArticleRelationService.onSummaryCompleted(
      _article('new-1'),
      const SummaryRecord(
        status: SummaryStatus.done,
        summaryText: '摘要',
        updatedAt: 1000,
      ),
    );
    await GStorage.relationBatches.put(
      'relation-000001',
      const ArticleRelationBatchRecord(
        id: 'relation-000001',
        status: 'failed',
        newArticleIds: ['new-1'],
        historyArticleIds: [],
        model: 'deepseek-v4-flash',
        promptVersion: 'relation-v1@test',
        schemaVersion: 1,
        startedAt: 1000,
        completedAt: 2000,
        error: '测试失败',
      ).toJson(),
    );
    var requestCount = 0;
    ArticleRelationWorker.debugRequestOverride = (input) async {
      requestCount++;
      return const ArticleRelationApiResult(groups: []);
    };

    await ArticleRelationWorker.initialize();
    ArticleRelationService.notifySummaryQueueIdle();
    await _waitForMicrotasks();
    expect(requestCount, 0);
    expect(ArticleRelationWorker.lastError.value, '测试失败');

    ArticleRelationWorker.retryPending();
    await _waitUntil(() => ArticleRelationService.pendingCount == 0);
    expect(requestCount, 1);
  });
}

ArticleModel _article(String id) {
  return ArticleModel(
    entryId: id,
    feedId: 'feed',
    feedTitle: '来源',
    title: id,
    url: 'https://example.com/$id',
    content: '<p>正文</p>',
    publishedAt: '2026-08-08T00:00:00Z',
  );
}

Future<void> _waitForMicrotasks() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('等待关系 worker 完成超时');
    }
    await _waitForMicrotasks();
  }
}

ArticleRelationNode _node(String id) {
  return ArticleRelationNode(
    articleId: id,
    sequence: 1,
    title: id,
    feedId: 'feed',
    feedTitle: '来源',
    url: 'https://example.com/$id',
    summary: '摘要',
    summaryDigest: 'digest',
    summaryUpdatedAt: 1,
  );
}
