import 'package:flutter/services.dart';

class MacOSZoomInCursor extends MouseCursor {
  const MacOSZoomInCursor._();

  static const instance = MacOSZoomInCursor._();
  static const _channel = MethodChannel('io.github.xraygit.fourier/cursor');

  @override
  MouseCursorSession createSession(int device) {
    return _MacOSZoomInCursorSession(this, device);
  }

  @override
  String get debugDescription => 'macOS zoomIn';
}

class _MacOSZoomInCursorSession extends MouseCursorSession {
  _MacOSZoomInCursorSession(super.cursor, super.device);

  @override
  Future<void> activate() async {
    try {
      await MacOSZoomInCursor._channel.invokeMethod<void>(
        'activateZoomInCursor',
      );
    } catch (_) {
      await SystemChannels.mouseCursor.invokeMethod<void>(
        'activateSystemCursor',
        <String, dynamic>{'device': device, 'kind': 'click'},
      );
    }
  }

  @override
  void dispose() {}
}
