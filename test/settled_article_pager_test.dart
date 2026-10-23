import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/pages/article/widgets/settled_article_pager.dart';

void main() {
  testWidgets(
    'prepares next neighbour only after snapping; cancelled drag retains page',
    (tester) async {
      final built = <int>{};
      var settled = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SettledArticlePager(
            initialPage: 0,
            itemCount: 5,
            onPageChanged: (_) {},
            onSettled: () => settled++,
            itemBuilder: (_, index) {
              built.add(index);
              return ColoredBox(
                color: Colors.white,
                child: Text('page $index'),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(built, {0, 1});
      final drag = await tester.startGesture(const Offset(700, 300));
      await drag.moveBy(const Offset(-100, 0));
      await tester.pump();
      await drag.moveBy(const Offset(-80, 0));
      await tester.pump();
      expect(built, {0, 1});
      final pageContext = tester.element(find.text('page 0'));
      expect(ReaderPreparationScope.allowed(pageContext), isFalse);
      await drag.moveBy(const Offset(-400, 0));
      await tester.pump();
      expect(built, {0, 1});
      expect(settled, 0);
      await drag.up();
      await tester.pumpAndSettle();
      expect(built, contains(2));
      expect(settled, 1);
      expect(
        ReaderPreparationScope.allowed(tester.element(find.text('page 1'))),
        isTrue,
      );

      final cancel = await tester.startGesture(const Offset(500, 300));
      await cancel.moveBy(const Offset(-60, 0));
      await tester.pump(const Duration(milliseconds: 200));
      await cancel.cancel();
      await tester.pumpAndSettle();
      expect(settled, 1);
      expect(
        ReaderPreparationScope.allowed(tester.element(find.text('page 1'))),
        isTrue,
      );
    },
  );

  testWidgets('fast continuous drag admits visible pages before settling', (
    tester,
  ) async {
    final built = <int>{};
    await tester.pumpWidget(
      MaterialApp(
        home: SettledArticlePager(
          initialPage: 0,
          itemCount: 6,
          onPageChanged: (_) {},
          itemBuilder: (_, index) {
            built.add(index);
            return Text('page $index');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final drag = await tester.startGesture(const Offset(700, 300));
    await drag.moveBy(const Offset(-50, 0));
    await tester.pump();
    await drag.moveBy(const Offset(-900, 0));
    await tester.pump();
    await tester.pump();
    expect(built, contains(2));
    expect(built, isNot(contains(3)));
    await drag.up();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'backward paging defers distant neighbour and can dispose mid-drag',
    (tester) async {
      final built = <int>{};
      await tester.pumpWidget(
        MaterialApp(
          home: SettledArticlePager(
            initialPage: 3,
            itemCount: 5,
            onPageChanged: (_) {},
            itemBuilder: (_, index) {
              built.add(index);
              return Text('page $index');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(built, {2, 3, 4});
      final drag = await tester.startGesture(const Offset(100, 300));
      await drag.moveBy(const Offset(50, 0));
      await tester.pump();
      await drag.moveBy(const Offset(500, 0));
      await tester.pump();
      expect(built, isNot(contains(1)));
      await drag.up();
      await tester.pumpAndSettle();
      expect(built, contains(1));
      final leaving = await tester.startGesture(const Offset(300, 300));
      await leaving.moveBy(const Offset(50, 0));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await leaving.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
