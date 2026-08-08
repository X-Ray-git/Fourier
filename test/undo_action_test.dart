import 'package:fourier/models/article.dart';
import 'package:fourier/services/bounded_history.dart';
import 'package:fourier/services/undo_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ArticleModel article(String id) => ArticleModel(
    entryId: id,
    feedId: 'feed-$id',
    feedTitle: 'Feed',
    title: 'Article $id',
    url: 'https://example.com/$id',
  );

  tearDown(UndoService.clear);

  test('a batch read occupies one global undo entry', () {
    UndoService.recordBatchRead([article('1'), article('2')]);

    expect(UndoService.canUndo, isTrue);
    expect(UndoService.nextUndoAction?.type, UndoActionType.batchRead);
    expect(UndoService.nextUndoAction?.articles, hasLength(2));
    expect(UndoService.nextUndoAction?.description, '将 2 篇静默文章标为已读');
  });

  test('partial batch undo splits restored and remaining history', () {
    final history = BoundedHistory<UndoAction>(limit: 50);
    final original = UndoAction.batchRead(
      sequence: 1,
      articles: [article('1'), article('2')],
    );
    history.push(original);
    expect(history.takeUndo(), same(original));

    history.resolvePartialUndo(
      original,
      undonePart: UndoAction.batchRead(sequence: 1, articles: [article('1')]),
      remainingPart: UndoAction.batchRead(
        sequence: 1,
        articles: [article('2')],
      ),
    );

    expect(history.nextUndo?.article.entryId, '2');
    expect(history.nextRedo?.article.entryId, '1');
  });

  test('partial batch redo splits redone and remaining history', () {
    final history = BoundedHistory<UndoAction>(limit: 50);
    final original = UndoAction.batchRead(
      sequence: 1,
      articles: [article('1'), article('2')],
    );
    history.push(original);
    expect(history.takeUndo(), same(original));

    history.resolvePartialRedo(
      original,
      redonePart: UndoAction.batchRead(sequence: 1, articles: [article('1')]),
      remainingPart: UndoAction.batchRead(
        sequence: 1,
        articles: [article('2')],
      ),
    );

    expect(history.nextUndo?.article.entryId, '1');
    expect(history.nextRedo?.article.entryId, '2');
  });

  test('custom action keeps callbacks and readable menu metadata', () async {
    var undoCalls = 0;
    var redoCalls = 0;
    final action = UndoAction.custom(
      sequence: 1,
      customActionName: '取消订阅',
      customDescription: '取消订阅《Example》',
      customTargetLabel: 'Example',
      customUndo: () async {
        undoCalls++;
        return true;
      },
      customRedo: () async {
        redoCalls++;
        return true;
      },
    );

    expect(action.type, UndoActionType.custom);
    expect(action.actionName, '取消订阅');
    expect(action.description, '取消订阅《Example》');
    expect(action.customTargetLabel, 'Example');
    expect(await action.customUndo!(), isTrue);
    expect(await action.customRedo!(), isTrue);
    expect(undoCalls, 1);
    expect(redoCalls, 1);
  });

  test('misclassify keep action carries menu metadata', () {
    final kept = ArticleModel(
      entryId: '1',
      feedId: 'f',
      feedTitle: 'F',
      title: 'T1',
      url: 'u',
      isRejectedByAi: true,
    );
    UndoService.recordMisclassifyAction(kept, reject: false);

    expect(UndoService.nextUndoAction?.type, UndoActionType.misclassifyKeep);
    expect(UndoService.nextUndoAction?.actionName, '移出垃圾拦截并标为已读');
    expect(UndoService.nextUndoAction?.description, '移出垃圾拦截并标为已读《T1》');
  });

  test('misclassify spam action carries menu metadata', () {
    final spam = ArticleModel(
      entryId: '2',
      feedId: 'f',
      feedTitle: 'F',
      title: 'T2',
      url: 'u',
    );
    UndoService.recordMisclassifyAction(spam, reject: true);

    expect(UndoService.nextUndoAction?.type, UndoActionType.misclassifySpam);
    expect(UndoService.nextUndoAction?.actionName, '移入垃圾拦截并标为已读');
    expect(UndoService.nextUndoAction?.description, '移入垃圾拦截并标为已读《T2》');
  });

  test('failed filter undo can rebuild the applied action snapshot', () {
    final original = ArticleModel(
      entryId: '3',
      feedId: 'f',
      feedTitle: 'F',
      title: 'T3',
      url: 'u',
      isRejectedByAi: true,
      filterReason: 'reason',
      filteredAt: 42,
    );

    final rejected = UndoService.appliedFilterSnapshot(
      UndoAction(
        sequence: 1,
        type: UndoActionType.filterReject,
        article: original,
      ),
    )!;
    expect(rejected.isRead, isTrue);
    expect(rejected.isRejectedByAi, isTrue);
    expect(rejected.filterReviewed, isTrue);
    expect(rejected.userAction, ArticleModel.userActionReject);

    final kept = UndoService.appliedFilterSnapshot(
      UndoAction(
        sequence: 2,
        type: UndoActionType.misclassifyKeep,
        article: original,
      ),
    )!;
    expect(kept.isRead, isTrue);
    expect(kept.isRejectedByAi, isFalse);
    expect(kept.filterReviewed, isTrue);
    expect(kept.filterReason, 'reason');
    expect(kept.filteredAt, 42);
    expect(kept.userAction, ArticleModel.userActionMisclassifyKeep);

    final spammed = UndoService.appliedFilterSnapshot(
      UndoAction(
        sequence: 3,
        type: UndoActionType.misclassifySpam,
        article: original,
      ),
    )!;
    expect(spammed.isRead, isTrue);
    expect(spammed.isRejectedByAi, isTrue);
    expect(spammed.filterReviewed, isTrue);
    expect(spammed.userAction, ArticleModel.userActionMisclassifySpam);
  });
}
