import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/common/widgets/mobile_edge_fade.dart';

void main() {
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
