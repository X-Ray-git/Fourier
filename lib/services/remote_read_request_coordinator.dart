import 'dart:async';

import 'account_session_guard.dart';

/// Serializes requests touching the same article. Other articles remain
/// concurrent; an unread request waits for an already transmitted read.
abstract final class RemoteReadRequestCoordinator {
  static final Map<(int, String), Future<void>> _tails = {};

  static Future<T> run<T>(
    Iterable<String> entryIds,
    Future<T> Function() operation,
  ) async {
    final revision = AccountSessionGuard.revision;
    final keys = entryIds.toSet().map((id) => (revision, id)).toList();
    final previous = <Future<void>>[for (final key in keys) ?_tails[key]];
    final done = Completer<void>();
    // Reserve all keys before waiting, so overlapping batches cannot deadlock.
    for (final key in keys) {
      _tails[key] = done.future;
    }
    try {
      await Future.wait(previous);
      return await operation();
    } finally {
      done.complete();
      for (final key in keys) {
        if (identical(_tails[key], done.future)) _tails.remove(key);
      }
    }
  }
}
