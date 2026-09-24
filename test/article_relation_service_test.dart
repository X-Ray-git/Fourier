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

  test('通过稳定组 ID 加入事件并保持近似重复子组', () async {
    await ArticleRelationService.resetForTest(activatedAt: 1);
    for (var index = 0; index < 3; index++) {
      await ArticleRelationService.onSummaryCompleted(
        _article(index),
        SummaryRecord(
          status: SummaryStatus.done,
          summaryText: '摘要 $index',
          updatedAt: 1000 + index,
        ),
      );
    }
    final first = await ArticleRelationService.prepareNextBatch(
      flushPartial: true,
    );
    await ArticleRelationService.completeBatch(first!, const [
      ArticleRelationCandidateGroup(
        kind: ArticleRelationKind.sameEvent,
        memberIds: ['article-0', 'article-1'],
        reason: '同一发布',
        topic: '机构发布模型。',
        confidence: 0.9,
      ),
      ArticleRelationCandidateGroup(
        kind: ArticleRelationKind.equivalent,
        memberIds: ['article-0', 'article-1'],
        reason: '内容可替代',
        confidence: 0.95,
      ),
    ]);

    await ArticleRelationService.onSummaryCompleted(
      _article(3),
      const SummaryRecord(
        status: SummaryStatus.done,
        summaryText: '摘要 3',
        updatedAt: 2000,
      ),
    );
    final second = await ArticleRelationService.prepareNextBatch(
      flushPartial: true,
    );
    await ArticleRelationService.completeBatch(second!, const [
      ArticleRelationCandidateGroup(
        kind: ArticleRelationKind.sameEvent,
        memberIds: ['article-3'],
        groupId: 'relation-000001-g1',
        topic: '机构发布新版模型。',
        reason: '同一发布的新增报道',
        confidence: 0.88,
      ),
    ]);

    final eventGroups = ArticleRelationService.groupsFor('article-0')
        .where((group) => group.kind == ArticleRelationKind.sameEvent)
        .toList();
    expect(eventGroups, hasLength(1));
    expect(eventGroups.single.id, 'relation-000001-g1');
    expect(eventGroups.single.topicHistory, ['机构发布模型。']);
    expect(eventGroups.single.topic, '机构发布新版模型。');
    expect(eventGroups.single.memberIds.toSet(), {
      'article-0',
      'article-1',
      'article-3',
    });
    expect(
      ArticleRelationService.groupsFor('article-0')
          .where((group) => group.kind == ArticleRelationKind.equivalent),
      hasLength(1),
    );
  });

  test('共享成员不能合并事件，重复关系不产生跨两级关系', () async {
    await ArticleRelationService.resetForTest(activatedAt: 1);
    for (var i = 0; i < 5; i++) {
      await ArticleRelationService.onSummaryCompleted(
        _article(i),
        SummaryRecord(
          status: SummaryStatus.done,
          summaryText: '摘要 $i',
          updatedAt: 1000 + i,
        ),
      );
    }
    final first = (await ArticleRelationService.prepareNextBatch(
      flushPartial: true,
    ))!;
    await ArticleRelationService.completeBatch(first, const [
      ArticleRelationCandidateGroup(
        kind: ArticleRelationKind.sameEvent,
        memberIds: ['article-0', 'article-1'],
        topic: '甲公司发布甲模型。',
        reason: '',
        confidence: .9,
      ),
      ArticleRelationCandidateGroup(
        kind: ArticleRelationKind.sameEvent,
        memberIds: ['article-2', 'article-3'],
        topic: '乙公司发布乙模型。',
        reason: '',
        confidence: .9,
      ),
      ArticleRelationCandidateGroup(
        kind: ArticleRelationKind.equivalent,
        memberIds: ['article-1', 'article-2'],
        reason: '独立重复关系',
        confidence: .9,
      ),
      ArticleRelationCandidateGroup(
        kind: ArticleRelationKind.sameEvent,
        memberIds: ['article-1', 'article-4'],
        topic: '不应通过重叠成员创建。',
        reason: '',
        confidence: .9,
      ),
    ]);
    expect(
      ArticleRelationService.allGroups().where(
        (g) => g.kind == ArticleRelationKind.sameEvent,
      ),
      hasLength(2),
    );
    expect(ArticleRelationService.groupsFor('article-4'), isEmpty);
    expect(
      ArticleRelationService.componentFor('article-0')
          .map((i) => i.node.articleId),
      ['article-1'],
    );
    await ArticleRelationService.onSummaryCompleted(
      _article(5),
      const SummaryRecord(
        status: SummaryStatus.done,
        summaryText: '桥接比较',
        updatedAt: 2000,
      ),
    );
    final next = (await ArticleRelationService.prepareNextBatch(
      flushPartial: true,
    ))!;
    await ArticleRelationService.completeBatch(next, const [
      ArticleRelationCandidateGroup(
        kind: ArticleRelationKind.sameEvent,
        groupId: 'relation-000001-g1',
        memberIds: ['article-2', 'article-5'],
        reason: '不得抢走其他事件的成员',
        confidence: .9,
      ),
      ArticleRelationCandidateGroup(
        kind: ArticleRelationKind.sameEvent,
        groupId: 'missing',
        memberIds: ['article-5'],
        reason: '不存在的组',
        confidence: .9,
      ),
    ]);
    expect(ArticleRelationService.groupsFor('article-5'), isEmpty);
    expect(ArticleRelationService.allGroups(), hasLength(3));
  });

  test('规则迁移清空派生状态，保留账本并拒绝旧批次写回', () async {
    await ArticleRelationService.resetForTest(activatedAt: 1);
    await ArticleRelationService.onSummaryCompleted(
      _article(0),
      const SummaryRecord(
        status: SummaryStatus.done,
        summaryText: '旧摘要',
        updatedAt: 1000,
      ),
    );
    final old = (await ArticleRelationService.prepareNextBatch(
      flushPartial: true,
    ))!;
    await GStorage.relationBatches.put('audit', {'status': 'done'});
    await GStorage.summaries.put('article-0', {
      'status': 'done',
      'summaryText': '旧摘要',
      'updatedAt': 1000,
    });
    await GStorage.articleRelations.put('__schema_version__', 3);
    await ArticleRelationService.migrateToAnchoredGroups();
    expect(ArticleRelationService.pendingCount, 0);
    expect(ArticleRelationService.historyCount, 0);
    expect(ArticleRelationService.groupCount, 0);
    expect(ArticleRelationService.nodeOf('article-0'), isNull);
    expect(GStorage.relationBatches.get('audit'), isNotNull);
    expect(GStorage.summaries.get('article-0'), isNotNull);
    expect(await ArticleRelationService.completeBatch(old, const []), isFalse);
    await ArticleRelationService.onSummaryCompleted(
      _article(0),
      const SummaryRecord(
        status: SummaryStatus.done,
        summaryText: '旧摘要',
        updatedAt: 1000,
      ),
    );
    expect(ArticleRelationService.pendingCount, 0);
    final boundary = ArticleRelationService.activatedAt;
    await ArticleRelationService.migrateToAnchoredGroups();
    expect(ArticleRelationService.activatedAt, boundary);
    await ArticleRelationService.onSummaryCompleted(
      _article(1),
      SummaryRecord(
        status: SummaryStatus.done,
        summaryText: '新规则摘要',
        updatedAt: boundary! + 1,
      ),
    );
    final next = (await ArticleRelationService.prepareNextBatch(
      flushPartial: true,
    ))!;
    expect(next.id, 'relation-000002');
    expect(next.newNodes.single.sequence, 2);
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
