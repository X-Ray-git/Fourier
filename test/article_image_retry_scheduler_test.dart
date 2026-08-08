import 'package:fourier/services/article_image_retry_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArticleImageRetryScheduler', () {
    test('uses each backoff once and reports exhaustion once', () {
      final timers = <_ManualTimer>[];
      var readyCount = 0;
      var exhaustedCount = 0;
      final scheduler = ArticleImageRetryScheduler(
        backoff: const [
          Duration(seconds: 1),
          Duration(seconds: 2),
          Duration(seconds: 4),
        ],
        timerFactory: (delay, callback) {
          final timer = _ManualTimer(delay, callback);
          timers.add(timer);
          return timer.cancel;
        },
      );

      RetryScheduleResult schedule() {
        return scheduler.schedule(
          'image',
          onReady: () => readyCount++,
          onExhausted: () => exhaustedCount++,
        );
      }

      expect(schedule(), RetryScheduleResult.scheduled);
      expect(timers.last.delay, const Duration(seconds: 1));
      expect(schedule(), RetryScheduleResult.pending);
      timers.last.fire();

      expect(schedule(), RetryScheduleResult.scheduled);
      expect(timers.last.delay, const Duration(seconds: 2));
      timers.last.fire();

      expect(schedule(), RetryScheduleResult.scheduled);
      expect(timers.last.delay, const Duration(seconds: 4));
      timers.last.fire();

      expect(readyCount, 3);
      expect(schedule(), RetryScheduleResult.exhausted);
      expect(schedule(), RetryScheduleResult.exhausted);
      expect(exhaustedCount, 1);
      expect(scheduler.isExhausted('image'), isTrue);
    });

    test('reset cancels pending work and starts again from first delay', () {
      final timers = <_ManualTimer>[];
      final scheduler = ArticleImageRetryScheduler(
        backoff: const [Duration(seconds: 1), Duration(seconds: 2)],
        timerFactory: (delay, callback) {
          final timer = _ManualTimer(delay, callback);
          timers.add(timer);
          return timer.cancel;
        },
      );

      scheduler.schedule('image', onReady: () {}, onExhausted: () {});
      scheduler.reset('image');

      expect(timers.first.canceled, isTrue);
      expect(scheduler.isWaiting('image'), isFalse);
      expect(
        scheduler.schedule('image', onReady: () {}, onExhausted: () {}),
        RetryScheduleResult.scheduled,
      );
      expect(timers.last.delay, const Duration(seconds: 1));
    });

    test('cancelWhere only removes matching image state', () {
      final timers = <_ManualTimer>[];
      final scheduler = ArticleImageRetryScheduler(
        backoff: const [Duration(seconds: 1)],
        timerFactory: (delay, callback) {
          final timer = _ManualTimer(delay, callback);
          timers.add(timer);
          return timer.cancel;
        },
      );
      for (final key in ['article-a:1', 'article-a:2', 'article-b:1']) {
        scheduler.schedule(key, onReady: () {}, onExhausted: () {});
      }

      scheduler.cancelWhere((key) => key.startsWith('article-a:'));

      expect(scheduler.isWaiting('article-a:1'), isFalse);
      expect(scheduler.isWaiting('article-a:2'), isFalse);
      expect(scheduler.isWaiting('article-b:1'), isTrue);
    });
  });
}

class _ManualTimer {
  _ManualTimer(this.delay, this._callback);

  final Duration delay;
  final void Function() _callback;
  bool canceled = false;
  bool _fired = false;

  void cancel() => canceled = true;

  void fire() {
    if (canceled || _fired) return;
    _fired = true;
    _callback();
  }
}
