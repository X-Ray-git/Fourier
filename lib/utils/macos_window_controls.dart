import 'dart:io';

import 'package:flutter/services.dart';

class MacOSWindowControls {
  const MacOSWindowControls._();

  static const _channel = MethodChannel(
    'io.github.xraygit.fourier/window_controls',
  );

  static Future<void> setTrafficLightsHidden(bool hidden) async {
    if (!Platform.isMacOS) return;
    await _channel.invokeMethod<void>('setTrafficLightsHidden', hidden);
  }

  static Future<void> setAppearance(String mode) async {
    if (!Platform.isMacOS) return;
    await _channel.invokeMethod<void>('setAppearance', mode);
  }

  static Future<void> setSidebarGlassGeometry({
    required double width,
    required double margin,
    required double radius,
  }) async {
    if (!Platform.isMacOS) return;
    await _channel.invokeMethod<void>('setSidebarGlassGeometry', {
      'width': width,
      'margin': margin,
      'radius': radius,
    });
  }
}
