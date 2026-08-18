import 'package:flutter/foundation.dart';

@immutable
final class AnimatedImagePlaybackState {
  const AnimatedImagePlaybackState({
    required this.windowActive,
    required this.nearViewport,
    required this.playing,
    required this.hasFrame,
  });

  final bool windowActive;
  final bool nearViewport;
  final bool playing;
  final bool hasFrame;

  @override
  bool operator ==(Object other) {
    return other is AnimatedImagePlaybackState &&
        other.windowActive == windowActive &&
        other.nearViewport == nearViewport &&
        other.playing == playing &&
        other.hasFrame == hasFrame;
  }

  @override
  int get hashCode =>
      Object.hash(windowActive, nearViewport, playing, hasFrame);
}

/// In-memory counters for diagnosing animated-image energy use.
///
/// This service never stores image URLs, article IDs, or other content.
abstract final class AnimatedImagePlaybackMonitor {
  static final Map<Object, AnimatedImagePlaybackState> _states = {};
  static int _frameCallbacks = 0;
  static int _streamResolves = 0;
  static int _stateChanges = 0;

  static void register(Object token) {
    _states[token] = const AnimatedImagePlaybackState(
      windowActive: true,
      nearViewport: false,
      playing: false,
      hasFrame: false,
    );
  }

  static void unregister(Object token) {
    _states.remove(token);
  }

  static void update(
    Object token, {
    required bool windowActive,
    required bool nearViewport,
    required bool playing,
    required bool hasFrame,
  }) {
    final next = AnimatedImagePlaybackState(
      windowActive: windowActive,
      nearViewport: nearViewport,
      playing: playing,
      hasFrame: hasFrame,
    );
    if (_states[token] == next) return;
    _states[token] = next;
    _stateChanges++;
  }

  static void recordFrameCallback() {
    _frameCallbacks++;
  }

  static void recordStreamResolve() {
    _streamResolves++;
  }

  static Map<String, int> takeSnapshot() {
    var nearViewport = 0;
    var playing = 0;
    var frozenOffscreen = 0;
    var frozenInactive = 0;
    var waitingForFirstFrame = 0;

    for (final state in _states.values) {
      if (state.nearViewport) nearViewport++;
      if (state.playing) {
        playing++;
      } else if (!state.windowActive && state.hasFrame) {
        frozenInactive++;
      } else if (!state.nearViewport && state.hasFrame) {
        frozenOffscreen++;
      } else if (!state.hasFrame) {
        waitingForFirstFrame++;
      }
    }

    final snapshot = <String, int>{
      'registered': _states.length,
      'nearViewport': nearViewport,
      'playing': playing,
      'frozenOffscreen': frozenOffscreen,
      'frozenInactive': frozenInactive,
      'waitingForFirstFrame': waitingForFirstFrame,
      'frameCallbacks': _frameCallbacks,
      'streamResolves': _streamResolves,
      'stateChanges': _stateChanges,
    };
    _frameCallbacks = 0;
    _streamResolves = 0;
    _stateChanges = 0;
    return snapshot;
  }

  @visibleForTesting
  static void resetForTesting() {
    _states.clear();
    _frameCallbacks = 0;
    _streamResolves = 0;
    _stateChanges = 0;
  }
}
