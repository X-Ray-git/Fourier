import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/pages/article/widgets/image_loading_placeholder.dart';

void main() {
  testWidgets('slow image uses a waiting message instead of frozen progress', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: ImageLoadingPlaceholder(size: 24, strokeWidth: 2),
          ),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('等待图片加载'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('tiny inline image uses compact waiting state without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: ImageLoadingPlaceholder(size: 16, strokeWidth: 2),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('等待图片加载'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
