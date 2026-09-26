import 'dart:convert';

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

  test('解析唯一关系类型、概述和用量，忽略纯历史操作', () {
    final result = ArticleRelationWorker.parseResponse(
      _response(
        [
          {
            'type': 'equivalent',
            'members': ['N001', 'H001'],
            'topic': '同一篇论文。',
            'confidence': .91,
          },
          {
            'type': 'equivalent',
            'members': ['H001', 'H002'],
            'topic': '纯历史。',
          },
        ],
        usage: {
          'prompt_cache_hit_tokens': 80,
          'prompt_cache_miss_tokens': 20,
          'total_tokens': 120,
        },
      ),
      {
        'N001': _node('new-1'),
        'H001': _node('history-1'),
        'H002': _node('history-2'),
      },
    );
    expect(result.groups, hasLength(1));
    expect(result.groups.single.kind, ArticleRelationKind.equivalent);
    expect(result.groups.single.topic, '同一篇论文。');
    expect(result.groups.single.memberIds, ['new-1', 'history-1']);
    expect(result.groups.single.confidence, .91);
    expect(result.cacheHitTokens, 80);
    expect(result.cacheMissTokens, 20);
    expect(result.totalTokens, 120);
  });

  test('旧 API 类型、缺失类型和缺失概述均报错，不能静默当无关系成功', () {
    for (final fields in [
      {'type': 'same_event', 'topic': '同一事件。'},
      {'type': 'unknown', 'topic': '未知。'},
      {'topic': '无类型。'},
      {'type': 'equivalent'},
      {'type': 'equivalent', 'topic': '   '},
      {'type': 'equivalent', 'topic': '暂无关系概述'},
      {
        'type': 'equivalent',
        'topic': ['错误类型'],
      },
    ]) {
      expect(
        () => ArticleRelationWorker.parseResponse(
          _response([
            {
              ...fields,
              'members': ['N001', 'H001'],
            },
          ]),
          {'N001': _node('new'), 'H001': _node('old')},
        ),
        throwsFormatException,
      );
    }
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
                  '{"type":"equivalent","members":["A000041","A000042"],"reason":"有效","topic":"重复原文。","confidence":0.9},'
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

  test('显式加入允许一个新成员、继承非空概述，旧空概述必须补充', () {
    const existing = ArticleRelationGroup(
      id: 'group-1',
      batchId: 'old',
      memberIds: ['old'],
      reason: '',
      confidence: .9,
      createdAt: 1,
      topic: '同一原文。',
    );
    const empty = ArticleRelationGroup(
      id: 'group-2',
      batchId: 'old',
      memberIds: ['old'],
      reason: '',
      confidence: .9,
      createdAt: 1,
    );
    final labels = {
      'A000041': _node('old', sequence: 41),
      'A000042': _node('new', sequence: 42),
    };
    final result = ArticleRelationWorker.parseResponse(
      _response([
        {
          'type': 'equivalent',
          'group_id': 'group-1',
          'members': ['A000042'],
          'topic': '',
        },
        {
          'type': 'equivalent',
          'group_id': 'missing',
          'members': ['A000042'],
        },
        {
          'type': 'equivalent',
          'group_id': 'group-1',
          'members': ['A000041'],
        },
      ]),
      labels,
      newLabels: {'A000042'},
      relationGroups: [existing],
    );
    expect(result.groups, hasLength(1));
    expect(result.groups.single.groupId, 'group-1');
    expect(result.groups.single.memberIds, ['new']);
    expect(
      () => ArticleRelationWorker.parseResponse(
        _response([
          {
            'type': 'equivalent',
            'group_id': 'group-2',
            'members': ['A000042'],
          },
        ]),
        labels,
        newLabels: {'A000042'},
        relationGroups: [empty],
      ),
      throwsFormatException,
    );
    final repaired = ArticleRelationWorker.parseResponse(
      _response([
        {
          'type': 'equivalent',
          'group_id': 'group-2',
          'members': ['A000042'],
          'topic': '共同原文概述。',
        },
      ]),
      labels,
      newLabels: {'A000042'},
      relationGroups: [empty],
    );
    expect(repaired.groups.single.topic, '共同原文概述。');
  });

  test('组上下文变化只影响后缀，自定义 Prompt 也保持稳定输入', () async {
    await ArticleRelationPromptService.setPrompt('用户修改的事件规则');
    expect(ArticleRelationPromptService.usesStableInputSchema, isTrue);
    final old = _node('old', sequence: 1);
    final fresh = _node('new', sequence: 2);
    final first = ArticleRelationWorker.buildUserPayload(
      ArticleRelationBatchInput(
        id: 'first',
        newNodes: [fresh],
        historyNodes: [old],
      ),
    );
    final second = ArticleRelationWorker.buildUserPayload(
      ArticleRelationBatchInput(
        id: 'second',
        newNodes: [fresh],
        historyNodes: [old],
        relationGroups: [
          const ArticleRelationGroup(
            id: 'legacy-overlap',
            batchId: 'old',
            memberIds: ['old'],
            reason: '',
            confidence: .9,
            createdAt: 1,
          ),
          const ArticleRelationGroup(
            id: 'event',
            batchId: 'old',
            memberIds: ['old'],
            reason: '',
            confidence: .9,
            createdAt: 1,
            kind: ArticleRelationKind.equivalent,
            topic: '具体事件。',
          ),
        ],
      ),
    );
    expect(second['articles'], first['articles']);
    expect(
      second.keys.toList().indexOf('relation_groups'),
      greaterThan(second.keys.toList().indexOf('articles')),
    );
    expect(second['article_group_ids'], {
      'A000001': ['legacy-overlap', 'event'],
    });
    expect((second['relation_groups'] as List).last['topic'], '具体事件。');
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
        promptVersion: 'relation-v5@test',
        schemaVersion: 5,
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

Map<String, dynamic> _response(
  List<Map<String, dynamic>> groups, {
  Map<String, int>? usage,
}) => {
  'choices': [
    {
      'finish_reason': 'stop',
      'message': {
        'content': jsonEncode({'groups': groups}),
      },
    },
  ],
  'usage': ?usage,
};
