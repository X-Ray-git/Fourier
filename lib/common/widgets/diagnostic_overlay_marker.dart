import 'package:flutter/widgets.dart';

import '../../services/ui_diagnostic_service.dart';

/// Records the lifetime of a mounted overlay without logging its content.
/// Queued notifications do not count as visible overlays until they mount.
class DiagnosticOverlayMarker extends StatefulWidget {
  const DiagnosticOverlayMarker({
    super.key,
    required this.kind,
    required this.child,
    this.requestId,
  });

  final String kind;
  final Widget child;
  final int? requestId;

  @override
  State<DiagnosticOverlayMarker> createState() =>
      _DiagnosticOverlayMarkerState();
}

class _DiagnosticOverlayMarkerState extends State<DiagnosticOverlayMarker> {
  late int _id;

  @override
  void initState() {
    super.initState();
    _open();
  }

  void _open() {
    final ancestors = <Map<String, Object?>>[];
    // runtimeType and element identity work in release. Do not stringify widgets
    // or keys: those can contain article text and URLs.
    try {
      context.visitAncestorElements((element) {
        ancestors.add({
          'elementId': identityHashCode(element),
          'component': element.widget.runtimeType.toString(),
        });
        return ancestors.length < 12;
      });
    } catch (_) {
      /* A diagnostic must not interrupt an overlay mount. */
    }
    _id = UiDiagnosticService.overlayOpened(
      widget.kind,
      requestId: widget.requestId,
      component: widget.child.runtimeType.toString(),
      ancestors: ancestors,
    );
  }

  @override
  void didUpdateWidget(covariant DiagnosticOverlayMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind ||
        oldWidget.requestId != widget.requestId) {
      UiDiagnosticService.overlayClosed(oldWidget.kind, _id);
      _open();
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
