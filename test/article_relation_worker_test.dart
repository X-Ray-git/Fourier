import 'package:flutter_test/flutter_test.dart';

import 'package:fourier/models/article.dart';
import 'package:fourier/models/article_relation.dart';
import 'package:fourier/services/article_relation_prompt_service.dart';
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

  test('文章从新批次进入历史后保持稳定 ID 与完整载荷', () {
    final first = _node('first', sequence: 41);
    final second = _node('second', sequence: 42);
    final firstPayload = ArticleRelationWorker.buildUserPayload(
      ArticleRelationBatchInput(
        id: 'batch-1',
        newNodes: [first],
        historyNodes: const [],
      ),
    );
    final secondPayload = ArticleRelationWorker.buildUserPayload(
      ArticleRelationBatchInput(
        id: 'batch-2',
        newNodes: [second],
        historyNodes: [first],
      ),
    );

    expect(firstPayload['new_ids'], ['A000041']);
    expect(secondPayload['new_ids'], ['A000042']);
    expect(
      (secondPayload['articles'] as List<dynamic>).first,
      (firstPayload['articles'] as List<dynamic>).first,
    );
  });

  test('稳定标签响应只接受包含本批 new_ids 的关系', () {
    final labels = {
      'A000041': _node('history', sequence: 41),
      'A000042': _node('new', sequence: 42),
    };
    final result = ArticleRelationWorker.parseResponse(
      {
        'choices': [
          {
            'finish_reason': 'stop',
            'message': {
              'content':
                  '{"groups":['
                  '{"type":"equivalent","members":["A000041","A000042"],"reason":"有效","confidence":0.9},'
                  '{"type":"equivalent","members":["A000041","A000099"],"reason":"无新文章","confidence":0.9}'
                  ']}',
            },
          },
        ],
      },
      labels,
      newLabels: {'A000042'},
    );

    expect(result.groups, hasLength(1));
    expect(result.groups.single.memberIds, ['history', 'new']);
  });

  test('启动时迁移已知旧默认 Prompt，但保留自定义 Prompt', () async {
    await GStorage.setting.put(
      ArticleRelationPromptService.storageKey,
      _legacyRelationDefaultPrompt,
    );
    await ArticleRelationWorker.initialize();
    expect(
      GStorage.setting.get(ArticleRelationPromptService.storageKey),
      ArticleRelationPromptService.defaultPrompt,
    );

    ArticleRelationWorker.resetForTest();
    await GStorage.setting.put(
      ArticleRelationPromptService.storageKey,
      '我的自定义关系规则',
    );
    await ArticleRelationWorker.initialize();
    expect(ArticleRelationPromptService.getPrompt(), '我的自定义关系规则');
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

ArticleRelationNode _node(String id, {int sequence = 1}) {
  return ArticleRelationNode(
    articleId: id,
    sequence: sequence,
    title: id,
    feedId: 'feed',
    feedTitle: '来源',
    url: 'https://example.com/$id',
    summary: '摘要',
    summaryDigest: 'digest',
    summaryUpdatedAt: 1,
  );
}

const _legacyRelationDefaultPrompt = '''
你是文章信息关系分析器。输入包含本批新文章 new 与历史文章 history，每篇只有元信息和摘要。

请建立两种稀疏、无向的文章关系：
1. equivalent（近似重复）：信息内容高度重合，阅读其中任意一篇后其余文章基本不再提供明显新增信息。
2. same_event（同一事件）：报道同一次明确发布、公告、事故或核心事实，但各文章仍包含不可互相替代的新增信息。

判断只基于内容关系，与文章是否已读、用户兴趣或质量无关。即使组内文章当前都未读，也可以建立关系。若一个同一事件组内存在近似重复子集，应同时输出一个覆盖该事件的 same_event 组和对应的 equivalent 子组。

不要为仅主题相近、同一人物、同一产品或同一领域的文章建立关系。后续独立评测、量化版本、生态适配或观点文章，若不是同一次核心发布事实，不属于 same_event。不要处理日报、周报、链接合集、综合摘要、纯图片或有效摘要不足的文章；不确定时不建立关系。每个输出组必须至少包含一个 N 开头的新文章 ID。

只返回 JSON 对象，不要 Markdown、解释或代码块。结构必须是：
{"groups":[{"type":"same_event","members":["N001","H003"],"reason":"简短说明共同的核心事件","confidence":0.0},{"type":"equivalent","members":["N001","H004"],"reason":"简短说明可替代的具体信息","confidence":0.0}]}

没有可靠关系时返回：{"groups":[]}
''';
