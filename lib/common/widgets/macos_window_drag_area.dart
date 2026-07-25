import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// An explicit macOS window drag region.
///
/// The window's implicit title-bar dragging is disabled. Only non-interactive
/// title and blank header areas should use this widget; controls must remain
/// siblings rather than descendants.
class MacOSWindowDragArea extends StatelessWidget {
  const MacOSWindowDragArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS) return child;
    return DragToMoveArea(
      child: SizedBox(width: double.infinity, child: child),
    );
  }
}
