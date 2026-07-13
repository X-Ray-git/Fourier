import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../../utils/macos_window_controls.dart';

/// Prevents macOS title-bar dragging while a Flutter control is pressed.
///
/// A transparent Flutter view can otherwise pass a small pointer movement to
/// AppKit's title-bar drag handling. Blank header areas remain draggable.
class MacOSWindowDragGuard extends StatefulWidget {
  const MacOSWindowDragGuard({super.key, required this.child});

  final Widget child;

  @override
  State<MacOSWindowDragGuard> createState() => _MacOSWindowDragGuardState();
}

class _MacOSWindowDragGuardState extends State<MacOSWindowDragGuard> {
  final Object _token = Object();
  final Set<int> _activePointers = {};

  void _handlePointerDown(PointerDownEvent event) {
    if (_activePointers.add(event.pointer) && _activePointers.length == 1) {
      _MacOSWindowMoveProtection.acquire(_token);
    }
  }

  void _handlePointerEnd(PointerEvent event) {
    if (!_activePointers.remove(event.pointer) || _activePointers.isNotEmpty) {
      return;
    }
    _MacOSWindowMoveProtection.release(_token);
  }

  @override
  void dispose() {
    _activePointers.clear();
    _MacOSWindowMoveProtection.release(_token);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS) return widget.child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerEnd,
      onPointerCancel: _handlePointerEnd,
      child: widget.child,
    );
  }
}

abstract final class _MacOSWindowMoveProtection {
  static final Set<Object> _holders = {};
  static Future<void> _pendingUpdate = Future<void>.value();

  static void acquire(Object token) {
    if (!_holders.add(token) || _holders.length != 1) return;
    _setMovable(false);
  }

  static void release(Object token) {
    if (!_holders.remove(token) || _holders.isNotEmpty) return;
    _setMovable(true);
  }

  static void _setMovable(bool movable) {
    _pendingUpdate = _pendingUpdate
        .then((_) => MacOSWindowControls.setMovable(movable))
        .catchError((Object _) {});
    unawaited(_pendingUpdate);
  }
}
