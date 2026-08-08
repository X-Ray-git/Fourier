import 'package:fourier/common/widgets/app_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

void main() {
  testWidgets('AppGlassIconButton forwards a variable icon weight', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppGlassIconButton(
            icon: Symbols.check_rounded,
            tooltip: '标为已读',
            iconWeight: 700,
            onPressed: () {},
          ),
        ),
      ),
    );

    final icon = tester.widget<Icon>(find.byIcon(Symbols.check_rounded));
    expect(icon.weight, 700);
  });
}
