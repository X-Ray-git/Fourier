import 'dart:async';

typedef RetryTimerFactory =
    void Function() Function(Duration delay, void Function() callback);

enum RetryScheduleResult { scheduled, pending, exhausted }

/// Tracks one-shot retry timers and bounded backoff attempts by cache key.
///
/// Download ownership stays with [ArticleImageCacheService]. Keeping timer and
/// attempt bookkeeping here makes the retry policy independently testable.
class ArticleImageRetryScheduler {
  ArticleImageRetryScheduler({
    required List<Duration> backoff,
    RetryTimerFactory? timerFactory,
  }) : _backoff = List.unmodifiable(backoff),
       _timerFactory = timerFactory ?? _createTimer;

  final List<Duration> _backoff;
  final RetryTimerFactory _timerFactory;
  final Map<String, int> _attempts = {};
  final Map<String, void Function()> _cancelTimers = {};
  final Set<String> _reportedExhaustion = {};

  static void Function() _createTimer(
    Duration delay,
    void Function() callback,
  ) {
    final timer = Timer(delay, callback);
    return timer.cancel;
  }

  bool isWaiting(String key) => _cancelTimers.containsKey(key);

  bool isExhausted(String key) =>
      (_attempts[key] ?? 0) >= _backoff.length && !isWaiting(key);

  Set<String> get trackedKeys => {
    ..._attempts.keys,
    ..._cancelTimers.keys,
    ..._reportedExhaustion,
  };

  RetryScheduleResult schedule(
    String key, {
    required void Function() onReady,
    required void Function() onExhausted,
  }) {
    if (isWaiting(key)) return RetryScheduleResult.pending;

    final attempt = _attempts[key] ?? 0;
    if (attempt >= _backoff.length) {
      if (_reportedExhaustion.add(key)) onExhausted();
      return RetryScheduleResult.exhausted;
    }

    _attempts[key] = attempt + 1;
    _cancelTimers[key] = _timerFactory(_backoff[attempt], () {
      _cancelTimers.remove(key);
      onReady();
    });
    return RetryScheduleResult.scheduled;
  }

  void reset(String key) {
    _cancelTimers.remove(key)?.call();
    _attempts.remove(key);
    _reportedExhaustion.remove(key);
  }

  void cancelWhere(bool Function(String key) predicate) {
    final keys = trackedKeys.where(predicate).toList(growable: false);
    for (final key in keys) {
      reset(key);
    }
  }
}
