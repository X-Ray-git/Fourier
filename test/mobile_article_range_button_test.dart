import 'package:fourier/common/widgets/mobile_article_range_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('uses the neutral foreground for both article ranges', (
    tester,
  ) async {
    const onSurface = Color(0xffd5d7dc);

    Future<Color?> pumpButton({required bool unreadOnly}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            colorScheme: ThemeData.dark().colorScheme.copyWith(
              primary: const Color(0xffff6d00),
              onSurface: onSurface,
            ),
          ),
          home: Scaffold(
            body: MobileArticleRangeButton(
              unreadOnly: unreadOnly,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      return tester.widget<Icon>(find.byType(Icon).first).color;
    }

    expect(await pumpButton(unreadOnly: true), onSurface);
    expect(await pumpButton(unreadOnly: false), onSurface);
  });

  testWidgets('selects the article range from the mobile sheet', (
    tester,
  ) async {
    bool? selectedUnreadOnly;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MobileArticleRangeButton(
              unreadOnly: true,
              onChanged: (value) => selectedUnreadOnly = value,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.filter_alt_rounded));
    await tester.pumpAndSettle();

    expect(find.text('文章范围'), findsOneWidget);
    expect(find.text('未读'), findsOneWidget);
    expect(find.text('全部'), findsOneWidget);

    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();

    expect(selectedUnreadOnly, isFalse);
    expect(find.text('文章范围'), findsNothing);
  });
}
