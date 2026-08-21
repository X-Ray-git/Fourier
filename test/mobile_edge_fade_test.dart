import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/common/widgets/mobile_edge_fade.dart';

void main() {
  test('top fade is smooth, monotonic, and preserves approved key values', () {
    final gradient = mobileTopEdgeGradient(
      background: Colors.white,
      totalExtent: 100,
      transitionStart: 20,
      transitionExtent: 80,
    );
    final colors = gradient.colors;
    final stops = gradient.stops!;

    for (var i = 1; i < colors.length; i++) {
      expect(colors[i].a, lessThanOrEqualTo(colors[i - 1].a));
      expect(stops[i], greaterThan(stops[i - 1]));
    }
    expect(colors.first.a, closeTo(0.85, 0.0001));
    final midpoint = stops.indexWhere((stop) => (stop - 0.6).abs() < 0.0001);
    expect(midpoint, isNonNegative);
    expect(colors[midpoint].a, closeTo(0.45, 0.0001));
    expect(colors.last.a, closeTo(0, 0.0001));
  });

  testWidgets('extended body uses the scaffold-provided top inset', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(400, 800),
            padding: EdgeInsets.only(top: 80),
            viewPadding: EdgeInsets.zero,
          ),
          child: const SizedBox(
            width: 400,
            height: 800,
            child: MobileEdgeFadeStack(
              showBottom: false,
              child: SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    final overlay = tester.widget<Positioned>(find.byType(Positioned));
    expect(
      overlay.height,
      80 - mobileEdgeTopOverlapExtent + mobileEdgeTopTransitionExtent,
    );
  });
}
