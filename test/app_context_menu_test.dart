import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/common/widgets/app_context_menu.dart';

void main() {
  test('anchors the menu at the pointer inside the overlay', () {
    final position = AppContextMenu.relativePositionFor(
      const Offset(250, 100),
      const Size(1000, 750),
    );

    expect(position.left, 250);
    expect(position.top, 100);
    expect(position.right, 750);
    expect(position.bottom, 650);
  });

  test('clamps an out-of-bounds pointer to the overlay', () {
    final position = AppContextMenu.relativePositionFor(
      const Offset(-20, 780),
      const Size(1000, 750),
    );

    expect(position.left, 0);
    expect(position.top, 750);
    expect(position.right, 1000);
    expect(position.bottom, 0);
  });
}
