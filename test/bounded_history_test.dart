import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/services/bounded_history.dart';

void main() {
  group('BoundedHistory', () {
    test('keeps only the newest values up to the limit', () {
      final history = BoundedHistory<int>(limit: 3);

      history.push(1);
      history.push(2);
      history.push(3);
      history.push(4);

      expect(history.undoCount, 3);
      expect(history.takeUndo(), 4);
      expect(history.takeUndo(), 3);
      expect(history.takeUndo(), 2);
      expect(history.takeUndo(), isNull);
    });

    test('moves values between undo and redo stacks', () {
      final history = BoundedHistory<String>(limit: 50);

      history.push('first');
      history.push('second');

      expect(history.takeUndo(), 'second');
      expect(history.nextUndo, 'first');
      expect(history.nextRedo, 'second');
      expect(history.takeRedo(), 'second');
      expect(history.nextUndo, 'second');
      expect(history.canRedo, isFalse);
    });

    test('a new action clears redo history', () {
      final history = BoundedHistory<String>(limit: 50);

      history.push('first');
      history.push('second');
      history.takeUndo();
      history.push('replacement');

      expect(history.canRedo, isFalse);
      expect(history.nextUndo, 'replacement');
    });

    test('can roll back a failed undo or redo transaction', () {
      final history = BoundedHistory<Object>(limit: 50);
      final action = Object();
      history.push(action);

      expect(history.takeUndo(), same(action));
      expect(history.rollbackUndo(action), isTrue);
      expect(history.nextUndo, same(action));

      expect(history.takeUndo(), same(action));
      expect(history.takeRedo(), same(action));
      expect(history.rollbackRedo(action), isTrue);
      expect(history.nextRedo, same(action));
    });

    test('removeWhere removes matching values from both stacks', () {
      final history = BoundedHistory<int>(limit: 50);
      history.push(1);
      history.push(2);
      history.push(3);
      history.takeUndo();

      history.removeWhere((value) => value.isOdd);

      expect(history.nextUndo, 2);
      expect(history.canRedo, isFalse);
    });
  });
}
