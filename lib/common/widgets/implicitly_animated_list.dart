import 'package:flutter/material.dart';

typedef ImplicitItemKey<T> = Object Function(T item);
typedef AnimatedItemBuilder<T> =
    Widget Function(
      BuildContext context,
      T item,
      int index,
      Animation<double> animation,
    );

class ImplicitlyAnimatedList<T> extends StatefulWidget {
  final List<T> items;
  final ImplicitItemKey<T> itemKey;
  final AnimatedItemBuilder<T> itemBuilder;
  final AnimatedItemBuilder<T>? removedItemBuilder;
  final Widget Function(BuildContext context, int index)? separatorBuilder;
  final Duration insertDuration;
  final Duration removeDuration;
  final Curve insertCurve;
  final Curve removeCurve;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;
  final ScrollController? controller;
  final bool shrinkWrap;

  const ImplicitlyAnimatedList({
    super.key,
    required this.items,
    required this.itemKey,
    required this.itemBuilder,
    this.removedItemBuilder,
    this.separatorBuilder,
    this.insertDuration = const Duration(milliseconds: 220),
    this.removeDuration = const Duration(milliseconds: 180),
    this.insertCurve = Curves.easeOutCubic,
    this.removeCurve = Curves.easeInCubic,
    this.padding,
    this.physics,
    this.controller,
    this.shrinkWrap = false,
  });

  @override
  State<ImplicitlyAnimatedList<T>> createState() =>
      _ImplicitlyAnimatedListState<T>();
}

class _ImplicitlyAnimatedListState<T> extends State<ImplicitlyAnimatedList<T>> {
  final _listKey = GlobalKey<AnimatedListState>();
  late List<T> _items;

  @override
  void initState() {
    super.initState();
    _items = List<T>.from(widget.items);
  }

  @override
  void didUpdateWidget(ImplicitlyAnimatedList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncItems();
  }

  void _syncItems() {
    final listState = _listKey.currentState;
    final nextItems = widget.items;
    if (listState == null) {
      _items = List<T>.from(nextItems);
      return;
    }

    final nextKeys = nextItems.map(widget.itemKey).toSet();
    for (var index = _items.length - 1; index >= 0; index--) {
      final item = _items[index];
      if (!nextKeys.contains(widget.itemKey(item))) {
        final removedItem = _items.removeAt(index);
        listState.removeItem(
          index,
          (context, animation) => _buildRemovedItem(
            context,
            removedItem,
            index,
            CurvedAnimation(
              parent: animation,
              curve: widget.removeCurve,
            ),
          ),
          duration: widget.removeDuration,
        );
      }
    }

    for (var index = 0; index < nextItems.length; index++) {
      final nextItem = nextItems[index];
      final nextKey = widget.itemKey(nextItem);

      if (index < _items.length && widget.itemKey(_items[index]) == nextKey) {
        _items[index] = nextItem;
        continue;
      }

      final existingIndex = _items.indexWhere(
        (item) => widget.itemKey(item) == nextKey,
      );
      if (existingIndex >= 0) {
        _items.removeAt(existingIndex);
        listState.removeItem(
          existingIndex,
          (context, animation) => const SizedBox.shrink(),
          duration: Duration.zero,
        );
        _items.insert(index, nextItem);
        listState.insertItem(index, duration: Duration.zero);
        continue;
      }

      _items.insert(index, nextItem);
      listState.insertItem(index, duration: widget.insertDuration);
    }
  }

  Widget _buildRemovedItem(
    BuildContext context,
    T item,
    int index,
    Animation<double> animation,
  ) {
    final builder = widget.removedItemBuilder ?? widget.itemBuilder;
    final child = builder(context, item, index, animation);
    return _withSeparator(context, index, animation, child);
  }

  Widget _withSeparator(
    BuildContext context,
    int index,
    Animation<double> animation,
    Widget child,
  ) {
    final separatorBuilder = widget.separatorBuilder;
    if (separatorBuilder == null || index >= _items.length - 1) {
      return child;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        child,
        SizeTransition(
          sizeFactor: animation,
          child: separatorBuilder(context, index),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedList(
      key: _listKey,
      initialItemCount: _items.length,
      padding: widget.padding,
      physics: widget.physics,
      controller: widget.controller,
      shrinkWrap: widget.shrinkWrap,
      itemBuilder: (context, index, animation) {
        if (index < 0 || index >= _items.length) {
          return const SizedBox.shrink();
        }
        final curved = CurvedAnimation(
          parent: animation,
          curve: widget.insertCurve,
        );
        final child = widget.itemBuilder(
          context,
          _items[index],
          index,
          curved,
        );
        return _withSeparator(context, index, kAlwaysCompleteAnimation, child);
      },
    );
  }
}
