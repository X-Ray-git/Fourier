import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// Shares the native macOS window focus state without registering one native
/// listener per widget.
abstract final class MacosWindowActivityService {
  static final ValueNotifier<bool> isActive = ValueNotifier<bool>(true);

  static _MacosWindowActivityListener? _listener;

  static Future<void> initialize() async {
    if (!Platform.isMacOS || _listener != null) return;

    final listener = _MacosWindowActivityListener();
    _listener = listener;
    windowManager.addListener(listener);
    try {
      isActive.value = await windowManager.isFocused();
    } catch (_) {
      isActive.value = true;
    }
  }

  static Future<void> refresh() async {
    if (!Platform.isMacOS) return;
    try {
      isActive.value = await windowManager.isFocused();
    } catch (_) {
      // Native focus events remain the source of truth if querying fails.
    }
  }
}

final class _MacosWindowActivityListener with WindowListener {
  @override
  void onWindowFocus() {
    MacosWindowActivityService.isActive.value = true;
  }

  @override
  void onWindowBlur() {
    MacosWindowActivityService.isActive.value = false;
  }

  @override
  void onWindowMinimize() {
    MacosWindowActivityService.isActive.value = false;
  }

  @override
  void onWindowRestore() {
    MacosWindowActivityService.refresh();
  }

  @override
  void onWindowClose() {
    MacosWindowActivityService.isActive.value = false;
  }
}
