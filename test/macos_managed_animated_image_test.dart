import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/pages/article/widgets/macos_managed_animated_image.dart';

void main() {
  test('uses a 200px preactivation margin around the viewport', () {
    const viewport = Rect.fromLTWH(0, 0, 800, 600);
    expect(
      isRectNearViewport(const Rect.fromLTWH(0, 790, 100, 20), viewport),
      isTrue,
    );
    expect(
      isRectNearViewport(const Rect.fromLTWH(0, 801, 100, 20), viewport),
      isFalse,
    );
  });

  test('plays only near the viewport while the window is active', () {
    expect(
      shouldPlayManagedAnimatedImage(windowActive: true, nearViewport: true),
      isTrue,
    );
    expect(
      shouldPlayManagedAnimatedImage(windowActive: false, nearViewport: true),
      isFalse,
    );
    expect(
      shouldPlayManagedAnimatedImage(windowActive: true, nearViewport: false),
      isFalse,
    );
  });
}
