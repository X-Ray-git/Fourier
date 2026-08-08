import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/common/widgets/mobile_blur_app_bar.dart';
import 'package:fourier/common/widgets/mobile_viewport_insets.dart';

void main() {
  testWidgets('extended body reuses Scaffold-provided app bar inset', (
    tester,
  ) async {
    late EdgeInsets extendedInset;
    late EdgeInsets regularInset;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(top: 24)),
          child: Scaffold(
            extendBodyBehindAppBar: true,
            appBar: const MobileBlurAppBar(),
            body: Builder(
              builder: (context) {
                extendedInset = MobileViewportInsets.listTopInset(context);
                regularInset = MobileViewportInsets.listTopInset(
                  context,
                  bodyExtendsBehindAppBar: false,
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );

    expect(extendedInset.top, 24 + mobileAppBarToolbarHeight);
    expect(regularInset, EdgeInsets.zero);
  });
}
