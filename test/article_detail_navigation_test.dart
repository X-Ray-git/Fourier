import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/pages/article/article_detail_navigation.dart';

void main() {
  testWidgets(
    'nested articles publish state until the last related route leaves',
    (tester) async {
      final states = <bool>[];
      final observer = ArticleDetailNavigation(states.add);
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          navigatorObservers: [observer],
          home: const Text('root'),
        ),
      );
      final b = _route('B');
      key.currentState!.push(b);
      await tester.pumpAndSettle();
      final a = _route('A again');
      key.currentState!.push(a);
      await tester.pumpAndSettle();
      expect(states, [true]);
      observer.pop(a);
      observer.pop(a); // One callback cannot pop both A and B.
      await tester.pumpAndSettle();
      expect(find.text('B'), findsOneWidget);
      expect(states, [true]);
      observer.pop(b, afterFrame: true);
      observer.pop(b, afterFrame: true);
      await tester.pumpAndSettle();
      expect(find.text('root'), findsOneWidget);
      expect(states, [true, false]);
      observer.dispose();
    },
  );

  testWidgets('scheduled post-read return cannot pop a newer article', (
    tester,
  ) async {
    final observer = ArticleDetailNavigation((_) {});
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        navigatorObservers: [observer],
        home: const Text('root'),
      ),
    );
    final b = _route('B');
    key.currentState!.push(b);
    await tester.pumpAndSettle();
    observer.pop(b, afterFrame: true);
    key.currentState!.push(_route('C'));
    await tester.pumpAndSettle();
    expect(find.text('C'), findsOneWidget);
    observer.dispose();
  });

  testWidgets(
    'disposed pane cannot publish stale state or run a queued return',
    (tester) async {
      final states = <bool>[];
      final observer = ArticleDetailNavigation(states.add);
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          navigatorObservers: [observer],
          home: const Text('root'),
        ),
      );
      final b = _route('B');
      key.currentState!.push(b);
      await tester.pumpAndSettle();
      observer.pop(b, afterFrame: true);
      observer.dispose();
      await tester.pumpAndSettle();
      expect(find.text('B'), findsOneWidget);
      key.currentState!.pop();
      await tester.pumpAndSettle();
      expect(states, [true]);
    },
  );
}

PageRoute<void> _route(String label) => PageRouteBuilder<void>(
  pageBuilder: (_, _, _) => Text(label),
  transitionDuration: Duration.zero,
  reverseTransitionDuration: Duration.zero,
);
