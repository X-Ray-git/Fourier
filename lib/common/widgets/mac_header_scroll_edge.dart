import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../liquid_glass/widgets/shared/glass_scroll_edge_effect.dart';
import 'no_overscroll_indicator_behavior.dart';

/// Shared macOS treatment for scroll content beneath a transparent header.
///
/// Callers include [headerHeight] in the scrollable's own top padding. The
/// first item therefore starts below the header, then dissolves underneath it
/// as the user scrolls.
class MacHeaderScrollEdge extends StatelessWidget {
  static const double fadeExtent = 24;
  static const double timelineScrollbarGutter = 9;

  final double headerHeight;
  final Widget header;
  final Widget body;

  const MacHeaderScrollEdge({
    super.key,
    required this.headerHeight,
    required this.header,
    required this.body,
  });

  static double contentTopPadding(double headerHeight, [double spacing = 0]) {
    return headerHeight + spacing;
  }

  static double opaqueExtent(double headerHeight) {
    return headerHeight / 2;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GlassScrollEdgeEffect(
            topFadeHeight: headerHeight + fadeExtent,
            fadeBottom: false,
            style: GlassScrollEdgeStyle.soft,
            fadeColor: Theme.of(context).colorScheme.surface,
            topOpaqueExtent: opaqueExtent(headerHeight),
            topFadeTrailingInset: timelineScrollbarGutter,
            child: ScrollConfiguration(
              behavior: _MacHeaderScrollBehavior(headerHeight: headerHeight),
              child: body,
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: headerHeight,
          child: header,
        ),
      ],
    );
  }
}

class _MacHeaderScrollBehavior extends NoOverscrollIndicatorBehavior {
  final double headerHeight;

  const _MacHeaderScrollBehavior({required this.headerHeight});

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return MacHeaderScrollbar(
      controller: details.controller,
      headerHeight: headerHeight,
      child: child,
    );
  }
}

class MacHeaderScrollbar extends StatelessWidget {
  final ScrollController? controller;
  final double headerHeight;
  final Widget child;

  const MacHeaderScrollbar({
    super.key,
    required this.controller,
    required this.headerHeight,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ScrollbarTheme.of(context);
    const idleStates = <WidgetState>{};
    const hoverStates = <WidgetState>{WidgetState.hovered};
    final cs = Theme.of(context).colorScheme;
    return _MacHeaderRawScrollbar(
      controller: controller,
      idleColor:
          theme.thumbColor?.resolve(idleStates) ??
          cs.onSurface.withValues(alpha: 0.22),
      hoverColor:
          theme.thumbColor?.resolve(hoverStates) ??
          cs.onSurface.withValues(alpha: 0.34),
      thickness: theme.thickness?.resolve(idleStates) ?? 8,
      radius: theme.radius ?? const Radius.circular(999),
      mainAxisMargin: theme.mainAxisMargin ?? 0,
      crossAxisMargin: theme.crossAxisMargin ?? 0,
      padding: EdgeInsets.only(
        top: headerHeight,
        bottom: MediaQuery.paddingOf(context).bottom,
      ),
      interactive: theme.interactive ?? true,
      notificationPredicate: (notification) => notification.depth == 0,
      child: child,
    );
  }
}

class _MacHeaderRawScrollbar extends RawScrollbar {
  final Color idleColor;
  final Color hoverColor;

  const _MacHeaderRawScrollbar({
    required super.child,
    required super.controller,
    required this.idleColor,
    required this.hoverColor,
    required super.thickness,
    required super.radius,
    required super.mainAxisMargin,
    required super.crossAxisMargin,
    required super.padding,
    required super.interactive,
    required super.notificationPredicate,
  }) : super(thumbColor: idleColor);

  @override
  RawScrollbarState<_MacHeaderRawScrollbar> createState() =>
      _MacHeaderRawScrollbarState();
}

class _MacHeaderRawScrollbarState
    extends RawScrollbarState<_MacHeaderRawScrollbar> {
  bool _hovered = false;

  @override
  void updateScrollbarPainter() {
    super.updateScrollbarPainter();
    scrollbarPainter.color = _hovered ? widget.hoverColor : widget.idleColor;
  }

  @override
  void handleHover(PointerHoverEvent event) {
    super.handleHover(event);
    final hovered = isPointerOverScrollbar(
      event.position,
      event.kind,
      forHover: true,
    );
    if (_hovered == hovered) return;
    _hovered = hovered;
    updateScrollbarPainter();
  }

  @override
  void handleHoverExit(PointerExitEvent event) {
    super.handleHoverExit(event);
    if (!_hovered) return;
    _hovered = false;
    updateScrollbarPainter();
  }
}
