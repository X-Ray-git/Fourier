import 'package:flutter/widgets.dart';

import '../../services/ui_diagnostic_service.dart';

/// Records the lifetime of a mounted overlay without logging its content.
/// Queued notifications do not count as visible overlays until they mount.
class DiagnosticOverlayMarker extends StatefulWidget {
  const DiagnosticOverlayMarker({
    super.key,
    required this.kind,
    required this.child,
  });

  final String kind;
  final Widget child;

  @override
  State<DiagnosticOverlayMarker> createState() =>
      _DiagnosticOverlayMarkerState();
}

class _DiagnosticOverlayMarkerState extends State<DiagnosticOverlayMarker> {
  late int _id;

  @override
  void initState() {
    super.initState();
    _id = UiDiagnosticService.overlayOpened(widget.kind);
  }

  @override
  void didUpdateWidget(covariant DiagnosticOverlayMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind) {
      UiDiagnosticService.overlayClosed(oldWidget.kind, _id);
      _id = UiDiagnosticService.overlayOpened(widget.kind);
    }
  }

  @override
  void dispose() {
    UiDiagnosticService.overlayClosed(widget.kind, _id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
