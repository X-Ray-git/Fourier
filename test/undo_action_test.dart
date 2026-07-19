import 'package:autofolo/models/article.dart';
import 'package:autofolo/services/bounded_history.dart';
import 'package:autofolo/services/undo_service.dart';
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
}
