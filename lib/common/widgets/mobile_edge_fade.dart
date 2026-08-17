import 'dart:math' as math;

import 'package:flutter/material.dart';

const mobileEdgeTopTransitionExtent = 56.0;
const mobileEdgeTopOverlapExtent = 24.0;
const mobileEdgeTopContentGap = 8.0;
// Android article cards already contribute 6px of outer top padding.
const mobileEdgeListTopPadding = 2.0;
const mobileEdgeBottomTransitionExtent = 24.0;
const mobileEdgeBottomMaxOpacity = 0.65;
const _fadeSampleCount = 21;

double _smoothStep(double value) => value * value * (3 - 2 * value);

LinearGradient mobileTopEdgeGradient({
  required Color background,
  required double totalExtent,
  required double transitionStart,
  double transitionExtent = mobileEdgeTopTransitionExtent,
}) {
  final transitionStartStop = (transitionStart / totalExtent).clamp(0.0, 1.0);
  final transitionEndStop = ((transitionStart + transitionExtent) / totalExtent)
      .clamp(0.0, 1.0);
  final transitionMidpointStop =
      ((transitionStart + transitionExtent / 2) / totalExtent).clamp(0.0, 1.0);
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      background.withValues(alpha: 0.85),
      background.withValues(alpha: 0.85),
      background.withValues(alpha: 0.45),
      background.withValues(alpha: 0),
    ],
    stops: [0, transitionStartStop, transitionMidpointStop, transitionEndStop],
  );
}

LinearGradient mobileBottomEdgeGradient({
  required Color background,
  required double totalExtent,
  double transitionExtent = mobileEdgeBottomTransitionExtent,
  double maxOpacity = mobileEdgeBottomMaxOpacity,
}) {
  final colors = <Color>[];
  final stops = <double>[];
  for (var i = 0; i < _fadeSampleCount; i++) {
    final progress = i / (_fadeSampleCount - 1);
    colors.add(
      background.withValues(alpha: _smoothStep(progress) * maxOpacity),
    );
    stops.add((transitionExtent * progress / totalExtent).clamp(0.0, 1.0));
  }
  colors.add(background.withValues(alpha: maxOpacity));
  stops.add(1);
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: colors,
    stops: stops,
  );
}

/// Android article surfaces fade scrolling content into the page background
/// instead of separating it with a blurred app bar.
class MobileEdgeFadeStack extends StatelessWidget {
  const MobileEdgeFadeStack({
    super.key,
    required this.child,
    this.topBarHeight = 48,
    this.bottomOpaqueExtent = 0,
    this.topTransitionExtent = mobileEdgeTopTransitionExtent,
    this.bottomTransitionExtent = mobileEdgeBottomTransitionExtent,
    this.bottomMaxOpacity = mobileEdgeBottomMaxOpacity,
    this.showTop = true,
    this.showBottom = true,
  });

  final Widget child;
  final double topBarHeight;
  final double bottomOpaqueExtent;
  final double topTransitionExtent;
  final double bottomTransitionExtent;
  final double bottomMaxOpacity;
  final bool showTop;
  final bool showBottom;

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).scaffoldBackgroundColor;
    final viewPadding = MediaQuery.viewPaddingOf(context);
    // Scaffold removes viewPadding.top from an extended body, then exposes the
    // complete status-bar + AppBar extent through padding.top. Keep the
    // viewPadding calculation as a fallback for standalone usage.
    final topOpaqueExtent = math.max(
      MediaQuery.paddingOf(context).top,
      viewPadding.top + topBarHeight,
    );
    final topTransitionStart = topOpaqueExtent - mobileEdgeTopOverlapExtent;
    final topOverlayExtent = topTransitionStart + topTransitionExtent;
    final bottomOpaque = viewPadding.bottom + bottomOpaqueExtent;

    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (showTop)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topOverlayExtent,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: mobileTopEdgeGradient(
                    background: background,
                    totalExtent: topOverlayExtent,
                    transitionStart: topTransitionStart,
                    transitionExtent: topTransitionExtent,
                  ),
                ),
              ),
            ),
          ),
        if (showBottom)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: bottomOpaque + bottomTransitionExtent,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: mobileBottomEdgeGradient(
                    background: background,
                    totalExtent: bottomOpaque + bottomTransitionExtent,
                    transitionExtent: bottomTransitionExtent,
                    maxOpacity: bottomMaxOpacity,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
