import 'dart:io';

import 'package:flutter/services.dart';

class MacOSWindowControls {
  const MacOSWindowControls._();

  static const _channel = MethodChannel(
    'io.github.xraygit.autofolo/window_controls',
  );

  static Future<void> setTrafficLightsHidden(bool hidden) async {
    if (!Platform.isMacOS) return;
    await _channel.invokeMethod<void>('setTrafficLightsHidden', hidden);
  }

  static Future<void> setMovable(bool movable) async {
    if (!Platform.isMacOS) return;
    await _channel.invokeMethod<void>('setMovable', movable);
  }
}
