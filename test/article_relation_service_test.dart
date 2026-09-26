import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/common/constants/constants.dart';
import 'package:fourier/models/article.dart';
import 'package:fourier/models/article_relation.dart';
import 'package:fourier/services/article_relation_service.dart';
import 'package:fourier/services/summary_service.dart';
import 'package:fourier/utils/storage.dart';

import 'support/hive_test_helper.dart';

void main() {
  setUp(HiveTestHelper.setUp);
  tearDown(HiveTestHelper.tearDown);

  test('默认关闭且关闭期间完成的摘要不进入待处理队列', () async {
    expect(ArticleRelationService.isEnabled, isFalse);

    await ArticleRelationService.onSummaryCompleted(
      _article(0),
      const SummaryRecord(
        status: SummaryStatus.done,
        summaryText: '关闭期间的摘要',
        updatedAt: 1000,
      ),
    );

    expect(ArticleRelationService.pendingCount, 0);
    expect(ArticleRelationService.nodeOf('article-0'), isNull);
  });

  test('只接收功能启用后完成的新摘要', () async {
    await ArticleRelationService.resetForTest(activatedAt: 1000);

    await ArticleRelationService.onSummaryCompleted(
      _article(1),
      const SummaryRecord(
        status: SummaryStatus.done,
        summaryText: '旧摘要',
        updatedAt: 999,
      ),
    );
    expect(ArticleRelationService.pendingCount, 0);

    await ArticleRelationService.onSummaryCompleted(
      _article(2),
      const SummaryRecord(
        status: SummaryStatus.done,
        summaryText: '新摘要',
        updatedAt: 1001,
      ),
    );
    expect(ArticleRelationService.pendingCount, 1);
  });

  test('账号清空后第一篇新摘要不会因激活时间晚几毫秒而丢失', () async {
    await ArticleRelationService.resetForTest();
    await GStorage.articleRelations.clear();
    ArticleRelationService.resetForAccountChange();

    await ArticleRelationService.onSummaryCompleted(
      _article(1),
      SummaryRecord(
        status: SummaryStatus.done,
        summaryText: '新账号第一篇摘要',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    expect(ArticleRelationService.pendingCount, 1);
  });

  test('启动恢复会补上 node 已写但 pending 未写的中断窗口', () async {
    await ArticleRelationService.resetForTest(activatedAt: 1);
    const summary = '等待恢复的摘要';
    final article = _article(7);
    final node = ArticleRelationNode(
      articleId: article.entryId,
      sequence: 1,
      title: article.title,
      feedId: article.feedId,
      feedTitle: article.feedTitle,
      url: article.url,
      summary: summary,
      summaryDigest: sha256.convert(utf8.encode(summary)).toString(),
      summaryUpdatedAt: 1000,
    );
    await GStorage.articleRelations.put(
      'node:${article.entryId}',
      node.toJson(),
    );

    await ArticleRelationService.onSummaryCompleted(
      article,
      const SummaryRecord(
        status: SummaryStatus.done,
        summaryText: summary,
        updatedAt: 1000,
      ),
    );

    expect(ArticleRelationService.pendingCount, 1);
  });

  test('历史窗口随成功批次增长至独立上限', () async {
    await ArticleRelationService.resetForTest(activatedAt: 1);

    final batchesToFill =
        ArticleRelationService.historyLimit ~/ ArticleRelationService.batchSize;
    for (var batch = 0; batch < batchesToFill; batch++) {
      for (
        var offset = 0;
        offset < ArticleRelationService.batchSize;
        offset++
      ) {
        final index = batch * ArticleRelationService.batchSize + offset;
        await ArticleRelationService.onSummaryCompleted(
          _article(index),
          SummaryRecord(
            status: SummaryStatus.done,
            summaryText: '摘要 $index',
            updatedAt: 1000 + index,
          ),
        );
      }

      final input = await ArticleRelationService.prepareNextBatch(
        flushPartial: false,
      );
      expect(input, isNotNull);
      expect(input!.newNodes.length, ArticleRelationService.batchSize);
      expect(
        input.historyNodes.length,
        batch == 0
            ? 0
            : (batch * ArticleRelationService.batchSize).clamp(
                0,
                ArticleRelationService.historyLimit,
              ),
      );

      // 在批次提交前，pending 和 history 都不能被提前推进。
      expect(
        ArticleRelationService.pendingCount,
        ArticleRelationService.batchSize,
      );
      expect(
        ArticleRelationService.historyCount,
        (batch * ArticleRelationService.batchSize).clamp(
          0,
          ArticleRelationService.historyLimit,
        ),
      );
      await ArticleRelationService.completeBatch(input, const []);
      expect(ArticleRelationService.pendingCount, 0);
    }

    expect(
      ArticleRelationService.historyCount,
      ArticleRelationService.historyLimit,
    );
  });

  test('历史窗口超限时按独立步长淘汰以稳定后续请求前缀', () async {
    await ArticleRelationService.resetForTest(activatedAt: 1);

    final batchesToFill =
        ArticleRelationService.historyLimit ~/ ArticleRelationService.batchSize;
    for (var batch = 0; batch < batchesToFill; batch++) {
      await _enqueueAndComplete(
        batch * ArticleRelationService.batchSize,
        ArticleRelationService.batchSize,
      );
    }
    expect(
      ArticleRelationService.historyCount,
      ArticleRelationService.historyLimit,
    );

    await _enqueueAndComplete(
      ArticleRelationService.historyLimit,
      1,
      flushPartial: true,
    );
    expect(
      ArticleRelationService.historyCount,
      ArticleRelationService.historyLimit +
          1 -
          ArticleRelationService.historyEvictionSize,
    );

    await _enqueueAndComplete(
      ArticleRelationService.historyLimit + 1,
      20,
      flushPartial: true,
    );
    expect(
      ArticleRelationService.historyCount,
      ArticleRelationService.historyLimit +
          21 -
          ArticleRelationService.historyEvictionSize,
    );
  });

  test('尾批只有显式 flushPartial 时才发车', () async {
    await ArticleRelationService.resetForTest(activatedAt: 1);
    for (var i = 0; i < 7; i++) {
      await ArticleRelationService.onSummaryCompleted(
        _article(i),
        SummaryRecord(
          status: SummaryStatus.done,
          summaryText: '摘要 $i',
          updatedAt: 1000 + i,
        ),
      );
    }

    expect(
      await ArticleRelationService.prepareNextBatch(flushPartial: false),
      isNull,
    );
    final tail = await ArticleRelationService.prepareNextBatch(
      flushPartial: true,
    );
    expect(tail?.newNodes.length, 7);
    expect(ArticleRelationService.pendingCount, 7);
  });

  test('批次准备后关闭开关会拒绝迟到结果', () async {
    await ArticleRelationService.resetForTest(activatedAt: 1);
    await ArticleRelationService.onSummaryCompleted(
      _article(0),
      const SummaryRecord(
        status: SummaryStatus.done,
        summaryText: '摘要 0',
        updatedAt: 1000,
      ),
    );
    final input = await ArticleRelationService.prepareNextBatch(
      flushPartial: true,
    );
    await GStorage.setting.put(StorageKeys.articleRelationEnabled, false);

    final committed = await ArticleRelationService.completeBatch(input!, const [
      ArticleRelationCandidateGroup(
        kind: ArticleRelationKind.equivalent,
        memberIds: ['article-0', 'article-1'],
        reason: '迟到结果',
        confidence: 0.9,
      ),
    ]);

    expect(committed, isFalse);
    expect(ArticleRelationService.groupCount, 0);
    expect(ArticleRelationService.historyCount, 0);
  });

  test('统一关系支持稳定 ID 加入并保留概述历史', () async {
    await ArticleRelationService.resetForTest(activatedAt: 1);
    await _enqueue(0, 2);
    final first = (await ArticleRelationService.prepareNextBatch(
      flushPartial: true,
    ))!;
    await ArticleRelationService.completeBatch(first, [
      _candidate(['article-0', 'article-1'], topic: '同一篇论文。'),
    ]);
    await _enqueue(2, 1);
    final second = (await ArticleRelationService.prepareNextBatch(
      flushPartial: true,
    ))!;
    expect(second.relationGroups, hasLength(1));
    await ArticleRelationService.completeBatch(second, [
      _candidate(
        ['article-2'],
        groupId: 'relation-000001-g1',
        topic: '同一篇关于记忆的论文。',
      ),
    ]);
    final group = ArticleRelationService.allGroups().single;
    expect(group.memberIds, ['article-0', 'article-1', 'article-2']);
    expect(group.topicHistory, ['同一篇论文。']);
    expect(group.topic, '同一篇关于记忆的论文。');
    await _enqueue(3, 1);
    final third = (await ArticleRelationService.prepareNextBatch(
      flushPartial: true,
    ))!;
    await ArticleRelationService.completeBatch(third, [
      _candidate(['article-3'], groupId: group.id),
    ]);
    expect(ArticleRelationService.allGroups().single.topic, group.topic);
  });

  test('新关系不合并组或转移成员，也不创建新的重叠归属', () async {
    await ArticleRelationService.resetForTest(activatedAt: 1);
    await _enqueue(0, 5);
    final first = (await ArticleRelationService.prepareNextBatch(
      flushPartial: true,
    ))!;
    await ArticleRelationService.completeBatch(first, [
      _candidate(['article-0', 'article-1'], topic: '甲原文。'),
      _candidate(['article-2', 'article-3'], topic: '乙原文。'),
      _candidate(['article-1', 'article-4'], topic: '不应借已有成员另建组。'),
    ]);
    expect(ArticleRelationService.allGroups(), hasLength(2));
    expect(ArticleRelationService.groupsFor('article-4'), isEmpty);
    await _enqueue(5, 1);
    final next = (await ArticleRelationService.prepareNextBatch(
      flushPartial: true,
    ))!;
    await ArticleRelationService.completeBatch(next, [
      _candidate(['article-2', 'article-5'], groupId: 'relation-000001-g1'),
      _candidate(['article-5'], groupId: 'missing'),
    ]);
    expect(ArticleRelationService.groupsFor('article-5'), isEmpty);
    expect(
      ArticleRelationService.componentFor('article-0')
          .map((i) => i.node.articleId),
      ['article-1'],
    );
  });

  test('旧类型迁移完整保留组、概述、重叠归属和队列，幂等且拒绝旧批次', () async {
    await ArticleRelationService.resetForTest(activatedAt: 1);
    await _enqueue(0, 3);
    final completed = (await ArticleRelationService.prepareNextBatch(
      flushPartial: true,
    ))!;
    await ArticleRelationService.completeBatch(completed, const []);
    await _enqueue(3, 1);
    final stale = (await ArticleRelationService.prepareNextBatch(
      flushPartial: true,
    ))!;
    final oldEvent = {
      'id': 'event',
      'batchId': 'old',
      'kind': 'same_event',
      'memberIds': ['article-0', 'article-1'],
      'reason': '历史理由',
      'topic': '已有概述。',
      'topicHistory': ['更早概述。'],
      'confidence': .8,
      'createdAt': 123,
      'enabled': true,
    };
    final oldDuplicate = {
      ...oldEvent,
      'id': 'duplicate',
      'kind': 'equivalent',
      'memberIds': ['article-1', 'article-2'],
      'topic': '',
    };
    await GStorage.articleRelations.putAll({
      'group:event': oldEvent,
      'group:duplicate': oldDuplicate,
      'group:disabled': {...oldEvent, 'id': 'disabled', 'enabled': false},
      '__schema_version__': 4,
    });
    await GStorage.relationBatches.put('audit', {'status': 'done'});
    await GStorage.summaries.put('article-0', {'summaryText': '原摘要'});
    await GStorage.setting.put(StorageKeys.articleRelationEnabled, false);
    final before = GStorage.articleRelations.toMap();
    await ArticleRelationService.migrateToSingleKind();
    final after = GStorage.articleRelations.toMap();
    expect(after.keys.toSet(), before.keys.toSet());
    for (final key in before.keys) {
      if (key == '__schema_version__') {
        expect(after[key], 5);
      } else if (key.toString().startsWith('group:')) {
        expect(after[key], {...(before[key] as Map), 'kind': 'equivalent'});
      } else {
        expect(after[key], before[key]);
      }
    }
    expect(GStorage.relationBatches.get('audit'), {'status': 'done'});
    expect(GStorage.summaries.get('article-0'), {'summaryText': '原摘要'});
    expect(ArticleRelationService.groupsFor('article-1'), hasLength(2));
    expect(
      ArticleRelationService.componentFor('article-0')
          .map((i) => i.node.articleId),
      ['article-1'],
    );
    expect(
      ArticleRelationService.groupsFor('article-2').single.displayTopic,
      '暂无关系概述',
    );
    await GStorage.setting.put(StorageKeys.articleRelationEnabled, true);
    expect(
      await ArticleRelationService.completeBatch(stale, const []),
      isFalse,
    );
    await ArticleRelationService.migrateToSingleKind();
    expect(GStorage.articleRelations.toMap(), after);
    final next = (await ArticleRelationService.prepareNextBatch(
      flushPartial: true,
    ))!;
    expect(next.id, 'relation-000003');
    expect(next.newNodes.single.sequence, 4);
    // The empty historical topic must be filled when adding a new member.
    await ArticleRelationService.completeBatch(next, [
      _candidate(['article-3'], groupId: 'duplicate', topic: '补充共同原文概述。'),
    ]);
    expect(
      ArticleRelationService.groupsFor('article-3').single.topic,
      '补充共同原文概述。',
    );
  });

  test('迁移可从部分写入状态恢复，也保留无 schema 的旧记录', () async {
    await ArticleRelationService.resetForTest(activatedAt: 1);
    await GStorage.articleRelations.delete('__schema_version__');
    await GStorage.articleRelations.putAll({
      'group:a': {
        'id': 'a',
        'kind': 'equivalent',
        'memberIds': ['a', 'b'],
      },
      'group:b': {
        'id': 'b',
        'kind': 'same_event',
        'memberIds': ['b', 'c'],
        'topic': '旧主题。',
      },
    });
    await ArticleRelationService.migrateToSingleKind();
    expect(ArticleRelationService.allGroups(), hasLength(2));
    expect(ArticleRelationService.allGroups().map((g) => g.kind).toSet(), {
      ArticleRelationKind.equivalent,
    });
    expect(ArticleRelationService.activatedAt, 1);
  });

  test('缺失概述时整个批次不落盘、不出队、不推进历史', () async {
    await ArticleRelationService.resetForTest(activatedAt: 1);
    await _enqueue(3, 4);
    final next = (await ArticleRelationService.prepareNextBatch(
      flushPartial: true,
    ))!;
    await expectLater(
      ArticleRelationService.completeBatch(next, [
        _candidate(['article-3', 'article-4'], topic: '有效概述。'),
        _candidate(['article-5', 'article-6']),
      ]),
      throwsFormatException,
    );
    expect(ArticleRelationService.pendingCount, 4);
    expect(ArticleRelationService.historyCount, 0);
    expect(ArticleRelationService.groupCount, 0);
    expect(ArticleRelationService.nodeOf('article-3')!.processedAt, isNull);
  });

  test('旧关系记录默认迁移为近似重复', () {
    final group = ArticleRelationGroup.fromJson({
      'id': 'legacy',
      'batchId': 'relation-000001',
      'memberIds': ['a', 'b'],
      'reason': '旧关系',
      'confidence': 0.9,
      'createdAt': 1,
    });

    expect(group.kind, ArticleRelationKind.equivalent);
  });
}

Future<void> _enqueueAndComplete(
  int start,
  int count, {
  bool flushPartial = false,
}) async {
  for (var offset = 0; offset < count; offset++) {
    final index = start + offset;
    await ArticleRelationService.onSummaryCompleted(
      _article(index),
      SummaryRecord(
        status: SummaryStatus.done,
        summaryText: '摘要 $index',
        updatedAt: 1000 + index,
      ),
    );
  }
  final input = await ArticleRelationService.prepareNextBatch(
    flushPartial: flushPartial,
  );
  expect(input, isNotNull);
  await ArticleRelationService.completeBatch(input!, const []);
}

ArticleModel _article(int index) {
  return ArticleModel(
    entryId: 'article-$index',
    feedId: 'feed-$index',
    feedTitle: '来源 $index',
    title: '文章 $index',
    url: 'https://example.com/$index',
    content: '<p>正文 $index</p>',
    publishedAt: '2026-08-08T00:00:00Z',
  );
}

Future<void> _enqueue(int start, int count) async {
  for (var i = start; i < start + count; i++) {
    await ArticleRelationService.onSummaryCompleted(
      _article(i),
      SummaryRecord(
        status: SummaryStatus.done,
        summaryText: '摘要 $i',
        updatedAt: 1000 + i,
      ),
    );
  }
}

ArticleRelationCandidateGroup _candidate(
  List<String> ids, {
  String? groupId,
  String topic = '',
}) => ArticleRelationCandidateGroup(
  kind: ArticleRelationKind.equivalent,
  memberIds: ids,
  groupId: groupId,
  topic: topic,
  reason: '重复依据',
  confidence: .9,
);
