import 'dart:io';

import 'package:flutter/services.dart';

class MacOSWebViewControls {
  const MacOSWebViewControls._();

  static const _channel = MethodChannel(
    'io.github.xraygit.autofolo/webview_controls',
  );

  static Future<void> enableElementFullscreen(int webViewIdentifier) async {
    if (!Platform.isMacOS) return;
    await _channel.invokeMethod<void>('enableElementFullscreen', {
      'webViewIdentifier': webViewIdentifier,
    });
  }
}
