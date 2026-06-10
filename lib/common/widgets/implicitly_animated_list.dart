import 'dart:async';

import 'package:flutter/material.dart';

typedef ImplicitItemKey<T> = Object Function(T item);
typedef AnimatedItemBuilder<T> =
    Widget Function(
      BuildContext context,
      T item,
      int index,
      Animation<double> animation,
    );
typedef AnimatedItemLifecycle<T> = void Function(T item);

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
  final AnimatedItemLifecycle<T>? onRemoveStart;
  final AnimatedItemLifecycle<T>? onRemoveEnd;
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
    this.onRemoveStart,
    this.onRemoveEnd,
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
        widget.onRemoveStart?.call(removedItem);
        listState.removeItem(
          index,
          (context, animation) => _buildRemovedItem(
            context,
            removedItem,
            index,
            CurvedAnimation(parent: animation, curve: widget.removeCurve),
          ),
          duration: widget.removeDuration,
        );
        _scheduleRemoveEnd(removedItem);
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
        _items.insert(index, nextItem);
        continue;
      }

      _items.insert(index, nextItem);
      listState.insertItem(index, duration: widget.insertDuration);
    }
  }

  void _scheduleRemoveEnd(T item) {
    final onRemoveEnd = widget.onRemoveEnd;
    if (onRemoveEnd == null) return;

    Future<void>.delayed(widget.removeDuration, () {
      if (!mounted) return;
      onRemoveEnd(item);
    });
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
        final child = widget.itemBuilder(context, _items[index], index, curved);
        return _withSeparator(context, index, kAlwaysCompleteAnimation, child);
      },
    );
  }
}

class DelayedVisibility extends StatefulWidget {
  final bool visible;
  final Duration delay;
  final Widget child;

  const DelayedVisibility({
    super.key,
    required this.visible,
    required this.child,
    this.delay = const Duration(milliseconds: 220),
  });

  @override
  State<DelayedVisibility> createState() => _DelayedVisibilityState();
}

class _DelayedVisibilityState extends State<DelayedVisibility> {
  Timer? _timer;
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _syncVisibility();
  }

  @override
  void didUpdateWidget(DelayedVisibility oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible ||
        oldWidget.delay != widget.delay) {
      _syncVisibility();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _syncVisibility() {
    _timer?.cancel();
    if (!widget.visible) {
      if (_show) setState(() => _show = false);
      return;
    }

    _timer = Timer(widget.delay, () {
      if (!mounted) return;
      setState(() => _show = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _show ? widget.child : const SizedBox.shrink();
  }
}
