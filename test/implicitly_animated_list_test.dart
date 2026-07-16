import 'package:autofolo/common/widgets/implicitly_animated_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('keeps removed item visible during its exit animation', (
    tester,
  ) async {
    final key = GlobalKey<_ListHarnessState>();
    final started = <String>[];
    final ended = <String>[];

    await tester.pumpWidget(
      _ListHarness(
        key: key,
        initialItems: const ['a', 'b'],
        onRemoveStart: started.add,
        onRemoveEnd: ended.add,
      ),
    );

    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);

    key.currentState!.setItems(const ['b']);
    await tester.pump();

    expect(started, const ['a']);
    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 90));

    expect(find.text('a'), findsOneWidget);
    expect(ended, isEmpty);

    await tester.pump(const Duration(milliseconds: 200));

    expect(ended, const ['a']);
    expect(find.text('a'), findsNothing);
    expect(find.text('b'), findsOneWidget);
  });

  testWidgets('reorders existing items without remove lifecycle callbacks', (
    tester,
  ) async {
    final key = GlobalKey<_ListHarnessState>();
    final started = <String>[];
    final ended = <String>[];

    await tester.pumpWidget(
      _ListHarness(
        key: key,
        initialItems: const ['a', 'b', 'c'],
        onRemoveStart: started.add,
        onRemoveEnd: ended.add,
      ),
    );

    key.currentState!.setItems(const ['c', 'b', 'a']);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(started, isEmpty);
    expect(ended, isEmpty);
    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);
    expect(find.text('c'), findsOneWidget);
  });

  testWidgets('batch update reconciles immediately without replacing scroll', (
    tester,
  ) async {
    final key = GlobalKey<_ListHarnessState>();
    final started = <String>[];
    final ended = <String>[];
    final initialItems = List<String>.generate(30, (index) => 'item-$index');

    await tester.pumpWidget(
      _ListHarness(
        key: key,
        initialItems: initialItems,
        onRemoveStart: started.add,
        onRemoveEnd: ended.add,
      ),
    );

    key.currentState!.jumpTo(240);
    await tester.pump();
    expect(key.currentState!.scrollOffset, 240);

    final nextItems = List<String>.from(initialItems)
      ..remove('item-25')
      ..add('item-30');
    key.currentState!.setItems(nextItems, batch: true);
    await tester.pump();
    await tester.pump(const Duration(microseconds: 1));

    expect(started, const ['item-25']);
    expect(ended, const ['item-25']);
    expect(find.text('item-25'), findsNothing);
    expect(key.currentState!.scrollOffset, 240);
  });
}

class _ListHarness extends StatefulWidget {
  final List<String> initialItems;
  final void Function(String item) onRemoveStart;
  final void Function(String item) onRemoveEnd;

  const _ListHarness({
    super.key,
    required this.initialItems,
    required this.onRemoveStart,
    required this.onRemoveEnd,
  });

  @override
  State<_ListHarness> createState() => _ListHarnessState();
}

class _ListHarnessState extends State<_ListHarness> {
  late List<String> _items = List<String>.from(widget.initialItems);
  final ScrollController _scrollController = ScrollController();
  int _batchUpdateVersion = 0;

  double get scrollOffset => _scrollController.offset;

  void jumpTo(double offset) => _scrollController.jumpTo(offset);

  void setItems(List<String> items, {bool batch = false}) {
    setState(() {
      _items = List<String>.from(items);
      if (batch) _batchUpdateVersion++;
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        height: 240,
        child: ImplicitlyAnimatedList<String>(
          items: _items,
          itemKey: (item) => item,
          batchUpdateVersion: _batchUpdateVersion,
          controller: _scrollController,
          removeDuration: const Duration(milliseconds: 180),
          onRemoveStart: widget.onRemoveStart,
          onRemoveEnd: widget.onRemoveEnd,
          itemBuilder: _buildItem,
          removedItemBuilder: _buildItem,
        ),
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    String item,
    int index,
    Animation<double> animation,
  ) {
    return SizeTransition(
      sizeFactor: animation,
      child: SizedBox(height: 32, child: Text(item)),
    );
  }
}
