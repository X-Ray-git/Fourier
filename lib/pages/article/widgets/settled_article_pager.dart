import 'package:flutter/material.dart';

import '../../../services/ui_diagnostic_service.dart';

/// Prepare neighbours only at rest. Visible pages are always admitted, including
/// fast consecutive swipes; an admitted page stays mounted until PageView evicts it.
class SettledArticlePager extends StatefulWidget {
  const SettledArticlePager({
    super.key,
    required this.initialPage,
    required this.itemCount,
    required this.itemBuilder,
    required this.onPageChanged,
    this.onSettled,
  });

  final int initialPage;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ValueChanged<int> onPageChanged;
  final VoidCallback? onSettled;

  @override
  State<SettledArticlePager> createState() => _SettledArticlePagerState();
}

class _SettledArticlePagerState extends State<SettledArticlePager> {
  late final PageController _controller;
  late int _settled;
  late int _firstVisible;
  late int _lastVisible;
  final Stopwatch _gesture = Stopwatch();
  bool _firstUpdate = false;
  bool _scrolling = false;
  int _scrollGeneration = 0;

  @override
  void initState() {
    super.initState();
    _settled = _firstVisible = _lastVisible = widget.initialPage;
    _controller = PageController(initialPage: widget.initialPage);
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics is! PageMetrics) {
      return false;
    }
    final page = (notification.metrics as PageMetrics).page!;
    if (notification is ScrollStartNotification) {
      _scrollGeneration++;
      setState(() => _scrolling = true);
    } else if (notification is ScrollUpdateNotification) {
      if (_firstUpdate && _gesture.isRunning) {
        _firstUpdate = false;
        UiDiagnosticService.recordReaderTiming(
          'pointer_to_scroll',
          _gesture.elapsedMicroseconds,
        );
        final firstFrame = Stopwatch()..start();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          UiDiagnosticService.recordReaderTiming(
            'first_scroll_to_frame_end',
            firstFrame.elapsedMicroseconds,
          );
        });
      }
      final first = page.floor();
      final last = page.ceil();
      if (first != _firstVisible || last != _lastVisible) {
        setState(() {
          _firstVisible = first;
          _lastVisible = last;
        });
      }
    } else if (notification is ScrollEndNotification) {
      final index = page.round();
      final changed = index != _settled;
      final generation = _scrollGeneration;
      // Let the final animation frame paint before admitting heavy neighbours.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _scrollGeneration) return;
        setState(() {
          _scrolling = false;
          _settled = _firstVisible = _lastVisible = index;
        });
        if (changed) widget.onSettled?.call();
      });
      _gesture.stop();
    }
    return false;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) {
      _gesture
        ..reset()
        ..start();
      _firstUpdate = true;
    },
    child: NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ReaderPreparationScope(
        canPrepare: !_scrolling,
        child: PageView.builder(
          controller: _controller,
          allowImplicitScrolling: true,
          itemCount: widget.itemCount,
          onPageChanged: widget.onPageChanged,
          itemBuilder: (context, index) => _PreparedPage(
            key: ValueKey(index),
            allowPreparation:
                (index - _settled).abs() <= 1 ||
                (index >= _firstVisible && index <= _lastVisible),
            builder: (context) => widget.itemBuilder(context, index),
          ),
        ),
      ),
    ),
  );
}

class _PreparedPage extends StatefulWidget {
  const _PreparedPage({
    super.key,
    required this.allowPreparation,
    required this.builder,
  });
  final bool allowPreparation;
  final WidgetBuilder builder;
  @override
  State<_PreparedPage> createState() => _PreparedPageState();
}

class _PreparedPageState extends State<_PreparedPage> {
  Widget? _page;
  @override
  Widget build(BuildContext context) {
    if (widget.allowPreparation) _page ??= widget.builder(context);
    return _page ?? const SizedBox.expand();
  }
}

/// Prevent a delayed/async first body build from starting during a page drag.
/// Already rendered bodies remain visible and keep their selection/scroll state.
class ReaderPreparationScope extends InheritedWidget {
  const ReaderPreparationScope({
    super.key,
    required this.canPrepare,
    required super.child,
  });
  final bool canPrepare;
  static bool allowed(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ReaderPreparationScope>()
          ?.canPrepare ??
      true;
  @override
  bool updateShouldNotify(ReaderPreparationScope oldWidget) =>
      canPrepare != oldWidget.canPrepare;
}
