import 'dart:async';

import 'package:flutter/services.dart';

typedef ArticleVideoPlaybackToggle = FutureOr<void> Function();

abstract final class ArticleVideoPlaybackShortcut {
  static Object? _activeOwner;
  static ArticleVideoPlaybackToggle? _togglePlayback;
  static DateTime? _lastToggleAt;
  static bool _isListening = false;

  static bool isActive(Object owner) => identical(_activeOwner, owner);

  static void activate(
    Object owner,
    ArticleVideoPlaybackToggle togglePlayback,
  ) {
    if (!identical(_activeOwner, owner)) {
      _lastToggleAt = null;
    }
    _activeOwner = owner;
    _togglePlayback = togglePlayback;
    if (_isListening) return;
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _isListening = true;
  }

  static void deactivate(Object owner) {
    if (!identical(_activeOwner, owner)) return;
    _activeOwner = null;
    _togglePlayback = null;
    _lastToggleAt = null;
    if (!_isListening) return;
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _isListening = false;
  }

  static bool requestToggle(Object owner) {
    if (!identical(_activeOwner, owner) || _togglePlayback == null) {
      return false;
    }

    final now = DateTime.now();
    final lastToggleAt = _lastToggleAt;
    if (lastToggleAt != null &&
        now.difference(lastToggleAt) < const Duration(milliseconds: 120)) {
      return true;
    }
    _lastToggleAt = now;
    unawaited(_invokeToggle(_togglePlayback!));
    return true;
  }

  static Future<void> _invokeToggle(
    ArticleVideoPlaybackToggle togglePlayback,
  ) async {
    try {
      await togglePlayback();
    } catch (_) {
      // The active platform view may have been disposed during navigation.
    }
  }

  static bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.space &&
        key != LogicalKeyboardKey.mediaPlayPause) {
      return false;
    }
    final owner = _activeOwner;
    return owner != null && requestToggle(owner);
  }
}
