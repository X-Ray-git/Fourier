import 'package:flutter/widgets.dart';

abstract final class MacOSLayoutMetrics {
  // Keep the native backdrop host/defaults in MainFlutterWindow.Metrics in sync.
  static const windowContentRadius = 18.0;
  static const sidebarExpandedWidth = 290.0;
  static const sidebarPanelMarginValue = 8.0;
  static const sidebarPanelRadius = windowContentRadius - 6.0;
  static const sidebarPanelMargin = EdgeInsets.all(sidebarPanelMarginValue);
}
