import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../liquid_glass/liquid_glass.dart';
import 'continuous_rectangle.dart';
import 'macos_window_drag_guard.dart';

enum AppGlassTone { surface, panel, control }

enum AppGlassButtonRole { primary, secondary, destructive }

enum AppGlassTooltipPlacement { bottom, right }

abstract final class AppGlassRadii {
  static const surface = 16.0;
  static const panel = 18.0;
  static const prominentPanel = 20.0;
  static const pill = 999.0;
}

Color appGlassActiveControlFill(
  BuildContext context, {
  double accentAlpha = 0.05,
}) {
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final neutralBase = isDark
      ? Colors.black.withValues(alpha: 0.22)
      : const Color(0xA6F4F7FC);
  return Color.alphaBlend(
    cs.primary.withValues(alpha: accentAlpha),
    neutralBase,
  );
}

class AppGlassControlPalette {
  final BuildContext context;
  late final ColorScheme _cs = Theme.of(context).colorScheme;
  late final bool _isDark = Theme.of(context).brightness == Brightness.dark;

  AppGlassControlPalette(this.context);

  Color get primaryForeground => _cs.primary;
  Color get neutralForeground => _cs.onSurface;
  Color get mutedForeground => _cs.onSurfaceVariant;
  Color get destructiveForeground => _cs.error;

  Color foregroundFor(AppGlassButtonRole role) {
    return switch (role) {
      AppGlassButtonRole.primary => primaryForeground,
      AppGlassButtonRole.secondary => neutralForeground,
      AppGlassButtonRole.destructive => destructiveForeground,
    };
  }

  Color activeFill({double accentAlpha = 0.05}) {
    return appGlassActiveControlFill(context, accentAlpha: accentAlpha);
  }

  Color activeTint({double darkAlpha = 0.20, double lightAlpha = 0.12}) {
    return _cs.primary.withValues(alpha: _isDark ? darkAlpha : lightAlpha);
  }

  Color activeBorder({double darkAlpha = 0.24, double lightAlpha = 0.18}) {
    return _cs.primary.withValues(alpha: _isDark ? darkAlpha : lightAlpha);
  }

  Color neutralOverlay({
    required bool hovered,
    required bool pressed,
    double darkHoverAlpha = 0.08,
    double lightHoverAlpha = 0.055,
    double darkPressedAlpha = 0.12,
    double lightPressedAlpha = 0.08,
  }) {
    final overlay = _isDark ? Colors.white : Colors.black;
    if (pressed) {
      return overlay.withValues(
        alpha: _isDark ? darkPressedAlpha : lightPressedAlpha,
      );
    }
    if (hovered) {
      return overlay.withValues(
        alpha: _isDark ? darkHoverAlpha : lightHoverAlpha,
      );
    }
    return Colors.transparent;
  }

  Color subtleNeutralOverlay({
    required bool hovered,
    required bool pressed,
    double hoverAlpha = 0.035,
    double pressedMultiplier = 1.2,
  }) {
    if (pressed) {
      return _cs.onSurface.withValues(
        alpha: (hoverAlpha * pressedMultiplier).clamp(0.0, 1.0),
      );
    }
    if (hovered) {
      return _cs.onSurface.withValues(alpha: hoverAlpha);
    }
    return Colors.transparent;
  }

  Color roleRestFill(AppGlassButtonRole role) {
    return switch (role) {
      AppGlassButtonRole.primary => activeFill(accentAlpha: 0.06),
      AppGlassButtonRole.destructive => Color.alphaBlend(
        _cs.error.withValues(alpha: 0.05),
        _cs.scrim.withValues(alpha: 0.18),
      ),
      AppGlassButtonRole.secondary => _cs.onSurface.withValues(alpha: 0.03),
    };
  }

  Color roleHoverFill(AppGlassButtonRole role) {
    return switch (role) {
      AppGlassButtonRole.primary => activeFill(accentAlpha: 0.065),
      AppGlassButtonRole.destructive => _cs.error.withValues(alpha: 0.045),
      AppGlassButtonRole.secondary => _cs.onSurface.withValues(alpha: 0.035),
    };
  }

  Color rolePressedFill(AppGlassButtonRole role) {
    final hoverFill = roleHoverFill(role);
    return hoverFill.withValues(alpha: (hoverFill.a * 1.2).clamp(0.0, 1.0));
  }

  Color optionFill({
    required bool selected,
    required bool hovered,
    required bool pressed,
  }) {
    if (selected) return activeTint();
    return neutralOverlay(hovered: hovered, pressed: pressed);
  }

  Color optionBorder({
    required bool selected,
    required bool hovered,
    double widthAlpha = 1.0,
  }) {
    if (selected) {
      final border = activeBorder();
      return border.withValues(alpha: border.a * widthAlpha);
    }
    if (hovered) {
      final border = neutralOverlay(hovered: true, pressed: false);
      return border.withValues(alpha: border.a * widthAlpha);
    }
    return Colors.transparent;
  }

  Color pillFill({required bool active}) {
    if (active) return activeFill(accentAlpha: 0.06);
    return _cs.surfaceContainerHighest.withValues(alpha: 0.58);
  }

  Color pillBorder({required bool active, required bool hovered}) {
    if (active) return _cs.primary.withValues(alpha: 0.22);
    return _cs.outlineVariant.withValues(alpha: hovered ? 0.62 : 0.52);
  }

  Color compactControlTrackFill() {
    return (_isDark ? Colors.white : Colors.black).withValues(
      alpha: _isDark ? 0.05 : 0.05,
    );
  }

  Color disabledFill() => _cs.onSurface.withValues(alpha: 0.03);
}

AppGlassControlPalette appGlassControlPalette(BuildContext context) {
  return AppGlassControlPalette(context);
}

LiquidGlassSettings appGlassSettingsFor(
  BuildContext context,
  AppGlassTone tone,
) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final tint = switch (tone) {
    AppGlassTone.surface =>
      isDark ? const Color(0x2AFFFFFF) : const Color(0x42FFFFFF),
    AppGlassTone.panel =>
      isDark ? const Color(0x32FFFFFF) : const Color(0x48FFFFFF),
    AppGlassTone.control =>
      isDark ? const Color(0x3AFFFFFF) : const Color(0x58FFFFFF),
  };
  return LiquidGlassSettings(
    blur: switch (tone) {
      AppGlassTone.surface => 14,
      AppGlassTone.panel => 18,
      AppGlassTone.control => 10,
    },
    thickness: switch (tone) {
      AppGlassTone.surface => 8,
      AppGlassTone.panel => 12,
      AppGlassTone.control => 7,
    },
    glassColor: tint,
    saturation: 1.18,
    refractiveIndex: 0.42,
    lightIntensity: isDark ? 0.62 : 0.74,
    ambientStrength: isDark ? 0.36 : 0.48,
    shadowElevation: !isDark && tone == AppGlassTone.control ? 1.25 : 1.0,
  );
}

LiquidGlassSettings appGlassButtonSettingsFor(BuildContext context) {
  final settings = appGlassSettingsFor(context, AppGlassTone.control);
  if (Theme.of(context).brightness != Brightness.dark) return settings;
  return settings.copyWith(
    glassColor: settings.glassColor.withValues(
      alpha: settings.glassColor.a * 0.86,
    ),
  );
}

Color appGlassBorderColor(BuildContext context, AppGlassTone tone) {
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  if (isDark) {
    return cs.outlineVariant.withValues(alpha: 0.22);
  }
  return tone == AppGlassTone.control
      ? cs.onSurface.withValues(alpha: 0.08)
      : cs.outlineVariant.withValues(alpha: 0.32);
}

class AppGlassSurface extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final AppGlassTone tone;
  final bool interactive;
  final bool useOwnLayer;
  final Clip clipBehavior;
  final bool nativeBackdrop;
  final bool staticMaterial;
  final double staticBorderOpacity;
  final double staticBorderWidth;
  final LiquidGlassSettings? settingsOverride;

  const AppGlassSurface({
    super.key,
    required this.child,
    this.borderRadius = AppGlassRadii.surface,
    this.padding,
    this.margin,
    this.tone = AppGlassTone.surface,
    this.interactive = false,
    this.useOwnLayer = true,
    this.clipBehavior = Clip.antiAlias,
    this.nativeBackdrop = false,
    this.staticMaterial = false,
    this.staticBorderOpacity = 1.0,
    this.staticBorderWidth = 0.75,
    this.settingsOverride,
  });

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS) {
      return _FallbackGlassSurface(
        borderRadius: borderRadius,
        padding: padding,
        margin: margin,
        child: child,
      );
    }

    if (staticMaterial) {
      return _StaticGlassSurface(
        borderRadius: borderRadius,
        padding: padding,
        margin: margin,
        tone: tone,
        borderOpacity: staticBorderOpacity,
        borderWidth: staticBorderWidth,
        child: child,
      );
    }

    if (nativeBackdrop) {
      return _NativeBackdropGlassSurface(
        borderRadius: borderRadius,
        padding: padding,
        margin: margin,
        child: child,
      );
    }

    final settings = settingsOverride ?? appGlassSettingsFor(context, tone);
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: AdaptiveGlass(
        shape: LiquidRoundedSuperellipse(borderRadius: borderRadius),
        settings: settings,
        quality: GlassQuality.standard,
        useOwnLayer: useOwnLayer,
        clipBehavior: clipBehavior,
        isInteractive: interactive,
        allowElevation: interactive,
        glowIntensity: interactive ? 0.18 : 0.0,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: appGlassBorderColor(context, tone),
              width: 0.5,
            ),
          ),
          child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
        ),
      ),
    );
  }
}

class _NativeBackdropGlassSurface extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const _NativeBackdropGlassSurface({
    required this.child,
    required this.borderRadius,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseTint = isDark
        ? Color.lerp(cs.surfaceContainerHighest, cs.scrim, 0.18)!
        : const Color(0xFFD2DCF0);
    final topTint = isDark
        ? Color.lerp(baseTint, cs.onSurface, 0.10)!
        : const Color(0xFFF7FAFF);
    final bottomTint = isDark
        ? Color.lerp(baseTint, cs.scrim, 0.22)!
        : const Color(0xFFE7EDF7);
    const rimColor = Colors.white;

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: CustomPaint(
        painter: _NativeBackdropShadowPainter(
          radius: borderRadius,
          isDark: isDark,
        ),
        child: ContinuousRectangleClip(
          radius: borderRadius,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: const SizedBox.expand(),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      topTint.withValues(alpha: isDark ? 0.30 : 0.24),
                      baseTint.withValues(alpha: isDark ? 0.24 : 0.20),
                      bottomTint.withValues(alpha: isDark ? 0.28 : 0.21),
                    ],
                    stops: const [0.0, 0.54, 1.0],
                  ),
                ),
                child: Padding(
                  padding: padding ?? EdgeInsets.zero,
                  child: child,
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _NativeBackdropRimPainter(
                      radius: borderRadius,
                      lightIntensity: isDark ? 0.28 : 0.34,
                      ambientStrength: isDark ? 0.05 : 0.07,
                      color: rimColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NativeBackdropShadowPainter extends CustomPainter {
  final double radius;
  final bool isDark;

  const _NativeBackdropShadowPainter({
    required this.radius,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = continuousRectanglePath(Offset.zero & size, radius);
    _drawShadow(
      canvas,
      path,
      color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.06),
      blurRadius: isDark ? 18 : 8,
      offset: Offset(0, isDark ? 6 : 2),
    );
    _drawShadow(
      canvas,
      path,
      color: Colors.black.withValues(alpha: isDark ? 0.14 : 0.035),
      blurRadius: isDark ? 3 : 2,
      offset: const Offset(0, 1),
    );
  }

  void _drawShadow(
    Canvas canvas,
    Path path, {
    required Color color,
    required double blurRadius,
    required Offset offset,
  }) {
    canvas.drawPath(
      path.shift(offset),
      Paint()
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurRadius),
    );
  }

  @override
  bool shouldRepaint(covariant _NativeBackdropShadowPainter oldDelegate) {
    return radius != oldDelegate.radius || isDark != oldDelegate.isDark;
  }
}

class _NativeBackdropRimPainter extends CustomPainter {
  static const _lightAngle = 0.75 * math.pi;

  final double radius;
  final double lightIntensity;
  final double ambientStrength;
  final Color color;

  const _NativeBackdropRimPainter({
    required this.radius,
    required this.lightIntensity,
    required this.ambientStrength,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final intensity = lightIntensity.clamp(0.0, 1.0);
    if (intensity == 0) return;

    final bounds = Offset.zero & size;
    final squareBounds = Rect.fromCircle(
      center: bounds.center,
      radius: bounds.size.longestSide / 2,
    );
    final rimColor = color.withValues(
      alpha: Curves.easeOut.transform(intensity) * 0.68,
    );
    final x = math.cos(_lightAngle);
    final y = -math.sin(_lightAngle);
    final lightCoverage = 0.3 + (0.5 - 0.3) * intensity;
    final shader = LinearGradient(
      colors: [
        rimColor,
        rimColor.withValues(alpha: ambientStrength),
        rimColor.withValues(alpha: ambientStrength),
        rimColor,
      ],
      stops: [0, lightCoverage, 1 - lightCoverage, 1],
      begin: Alignment(x, y),
      end: Alignment(-x, -y),
    ).createShader(squareBounds);
    final path = continuousRectanglePath(
      bounds.deflate(0.75),
      (radius - 0.5).clamp(0.0, double.infinity),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: intensity * 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.35,
    );
  }

  @override
  bool shouldRepaint(covariant _NativeBackdropRimPainter oldDelegate) {
    return radius != oldDelegate.radius ||
        lightIntensity != oldDelegate.lightIntensity ||
        ambientStrength != oldDelegate.ambientStrength ||
        color != oldDelegate.color;
  }
}

class AppGlassPanel extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  const AppGlassPanel({
    super.key,
    required this.child,
    this.borderRadius = AppGlassRadii.panel,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    return AppGlassSurface(
      borderRadius: borderRadius,
      padding: padding,
      tone: AppGlassTone.panel,
      child: child,
    );
  }
}

class AppGlassTooltip extends StatefulWidget {
  final String message;
  final Widget child;
  final Duration waitDuration;
  final AppGlassTooltipPlacement placement;

  const AppGlassTooltip({
    super.key,
    required this.message,
    required this.child,
    this.waitDuration = const Duration(milliseconds: 420),
    this.placement = AppGlassTooltipPlacement.bottom,
  });

  @override
  State<AppGlassTooltip> createState() => _AppGlassTooltipState();
}

class _AppGlassTooltipState extends State<AppGlassTooltip> {
  final GlobalKey _targetKey = GlobalKey();
  Timer? _timer;
  OverlayEntry? _entry;

  @override
  void dispose() {
    _timer?.cancel();
    _removeTooltip();
    super.dispose();
  }

  void _scheduleTooltip() {
    if (widget.message.trim().isEmpty) return;
    _timer?.cancel();
    _timer = Timer(widget.waitDuration, _showTooltip);
  }

  void _showTooltip() {
    if (!mounted || _entry != null) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    final theme = Theme.of(context);
    final textScale = MediaQuery.textScalerOf(context);
    _entry = OverlayEntry(
      builder: (context) {
        final targetBox =
            _targetKey.currentContext?.findRenderObject() as RenderBox?;
        final overlayBox = overlay.context.findRenderObject() as RenderBox?;
        if (targetBox == null ||
            overlayBox == null ||
            !targetBox.attached ||
            !overlayBox.attached) {
          return const SizedBox.shrink();
        }
        final targetGlobal = targetBox.localToGlobal(Offset.zero);
        final overlayGlobal = overlayBox.localToGlobal(Offset.zero);
        final targetRect = (targetGlobal - overlayGlobal) & targetBox.size;
        final resolvedPlacement = _resolveTooltipPlacement(
          placement: widget.placement,
          targetRect: targetRect,
          overlaySize: overlayBox.size,
          bubbleSize: _measureTooltipBubble(
            widget.message,
            textScale,
            Directionality.of(context),
          ),
        );
        final scaleAlignment = switch (resolvedPlacement) {
          _ResolvedTooltipPlacement.below => Alignment.topCenter,
          _ResolvedTooltipPlacement.above => Alignment.bottomCenter,
          _ResolvedTooltipPlacement.right => Alignment.centerLeft,
          _ResolvedTooltipPlacement.left => Alignment.centerRight,
        };
        return Theme(
          data: theme,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScale),
            child: Positioned.fill(
              child: IgnorePointer(
                child: CustomSingleChildLayout(
                  delegate: _AppGlassTooltipLayoutDelegate(
                    targetRect: targetRect,
                    placement: resolvedPlacement,
                  ),
                  child: _AppGlassTooltipBubble(
                    message: widget.message,
                    scaleAlignment: scaleAlignment,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_entry!);
  }

  void _hideTooltip() {
    _timer?.cancel();
    _removeTooltip();
  }

  void _removeTooltip() {
    _entry?.remove();
    _entry = null;
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS) {
      return Tooltip(message: widget.message, child: widget.child);
    }

    return Semantics(
      tooltip: widget.message,
      child: MouseRegion(
        key: _targetKey,
        onEnter: (_) => _scheduleTooltip(),
        onExit: (_) => _hideTooltip(),
        child: widget.child,
      ),
    );
  }
}

const _tooltipGap = 9.0;
const _tooltipEdgeMargin = 8.0;
const _tooltipMaxTextWidth = 260.0;

enum _ResolvedTooltipPlacement { below, above, right, left }

Size _measureTooltipBubble(
  String message,
  TextScaler textScaler,
  TextDirection textDirection,
) {
  final painter = TextPainter(
    text: TextSpan(
      text: message,
      style: const TextStyle(
        fontSize: 12,
        height: 1.25,
        fontWeight: FontWeight.w600,
      ),
    ),
    maxLines: 2,
    ellipsis: '…',
    textScaler: textScaler,
    textDirection: textDirection,
  )..layout(maxWidth: _tooltipMaxTextWidth);
  return Size(painter.width + 20, painter.height + 14);
}

_ResolvedTooltipPlacement _resolveTooltipPlacement({
  required AppGlassTooltipPlacement placement,
  required Rect targetRect,
  required Size overlaySize,
  required Size bubbleSize,
}) {
  switch (placement) {
    case AppGlassTooltipPlacement.bottom:
      final below = targetRect.bottom + _tooltipGap;
      final above = targetRect.top - _tooltipGap - bubbleSize.height;
      return below + bubbleSize.height <=
                  overlaySize.height - _tooltipEdgeMargin ||
              above < _tooltipEdgeMargin
          ? _ResolvedTooltipPlacement.below
          : _ResolvedTooltipPlacement.above;
    case AppGlassTooltipPlacement.right:
      final right = targetRect.right + _tooltipGap;
      final left = targetRect.left - _tooltipGap - bubbleSize.width;
      return right + bubbleSize.width <=
                  overlaySize.width - _tooltipEdgeMargin ||
              left < _tooltipEdgeMargin
          ? _ResolvedTooltipPlacement.right
          : _ResolvedTooltipPlacement.left;
  }
}

class _AppGlassTooltipLayoutDelegate extends SingleChildLayoutDelegate {
  final Rect targetRect;
  final _ResolvedTooltipPlacement placement;

  const _AppGlassTooltipLayoutDelegate({
    required this.targetRect,
    required this.placement,
  });

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(
      Size(
        math.max(0, constraints.maxWidth - _tooltipEdgeMargin * 2),
        math.max(0, constraints.maxHeight - _tooltipEdgeMargin * 2),
      ),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxX = math.max(
      _tooltipEdgeMargin,
      size.width - childSize.width - _tooltipEdgeMargin,
    );
    final maxY = math.max(
      _tooltipEdgeMargin,
      size.height - childSize.height - _tooltipEdgeMargin,
    );

    double x;
    double y;
    switch (placement) {
      case _ResolvedTooltipPlacement.below:
        x = targetRect.center.dx - childSize.width / 2;
        y = targetRect.bottom + _tooltipGap;
      case _ResolvedTooltipPlacement.above:
        x = targetRect.center.dx - childSize.width / 2;
        y = targetRect.top - _tooltipGap - childSize.height;
      case _ResolvedTooltipPlacement.right:
        x = targetRect.right + _tooltipGap;
        y = targetRect.center.dy - childSize.height / 2;
      case _ResolvedTooltipPlacement.left:
        x = targetRect.left - _tooltipGap - childSize.width;
        y = targetRect.center.dy - childSize.height / 2;
    }

    return Offset(
      x.clamp(_tooltipEdgeMargin, maxX).toDouble(),
      y.clamp(_tooltipEdgeMargin, maxY).toDouble(),
    );
  }

  @override
  bool shouldRelayout(covariant _AppGlassTooltipLayoutDelegate oldDelegate) {
    return targetRect != oldDelegate.targetRect ||
        placement != oldDelegate.placement;
  }
}

class _AppGlassTooltipBubble extends StatelessWidget {
  final String message;
  final Alignment scaleAlignment;

  const _AppGlassTooltipBubble({
    required this.message,
    this.scaleAlignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.scale(
            scale: 0.97 + value * 0.03,
            alignment: scaleAlignment,
            child: child,
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: AppGlassSurface(
          borderRadius: 11,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          tone: AppGlassTone.control,
          nativeBackdrop: true,
          useOwnLayer: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _tooltipMaxTextWidth),
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.25,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppGlassIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final bool useOwnLayer;

  const AppGlassIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.selected = false,
    this.useOwnLayer = true,
  });

  @override
  State<AppGlassIconButton> createState() => _AppGlassIconButtonState();
}

class AppGlassRoundControlChrome extends StatelessWidget {
  final Widget child;
  final bool enabled;
  final bool hovered;
  final bool pressed;
  final bool useOwnLayer;
  final double size;

  const AppGlassRoundControlChrome({
    super.key,
    required this.child,
    required this.enabled,
    required this.hovered,
    required this.pressed,
    this.useOwnLayer = true,
    this.size = 34,
  });

  @override
  Widget build(BuildContext context) {
    final controls = appGlassControlPalette(context);
    final fill = controls.subtleNeutralOverlay(
      hovered: enabled && hovered,
      pressed: enabled && pressed,
      hoverAlpha: 0.06,
    );

    return MacOSWindowDragGuard(
      child: AppGlassSurface(
        borderRadius: 999,
        padding: EdgeInsets.zero,
        tone: AppGlassTone.control,
        interactive: enabled,
        useOwnLayer: useOwnLayer,
        settingsOverride: appGlassButtonSettingsFor(context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: fill,
          ),
          child: child,
        ),
      ),
    );
  }
}

class AppGlassCompactSwitch extends StatefulWidget {
  final int selectedIndex;
  final List<String> labels;
  final ValueChanged<int> onChanged;
  final double trackWidth;
  final double trackHeight;
  final double thumbWidth;

  const AppGlassCompactSwitch({
    super.key,
    required this.selectedIndex,
    required this.labels,
    required this.onChanged,
    this.trackWidth = 58,
    this.trackHeight = 30,
    this.thumbWidth = 42,
  }) : assert(labels.length == 2),
       assert(selectedIndex == 0 || selectedIndex == 1);

  @override
  State<AppGlassCompactSwitch> createState() => _AppGlassCompactSwitchState();
}

class _AppGlassCompactSwitchState extends State<AppGlassCompactSwitch> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final controls = appGlassControlPalette(context);

    return MacOSWindowDragGuard(
      child: SelectionContainer.disabled(
        child: AppGlassSurface(
          borderRadius: AppGlassRadii.pill,
          padding: EdgeInsets.zero,
          tone: AppGlassTone.control,
          nativeBackdrop: true,
          staticMaterial: true,
          staticBorderOpacity: 1,
          staticBorderWidth: 1,
          child: SizedBox(
            width: widget.trackWidth,
            height: widget.trackHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppGlassRadii.pill),
                color: controls.compactControlTrackFill(),
              ),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() {
                  _hovered = false;
                  _pressed = false;
                }),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (_) => setState(() => _pressed = true),
                  onTapUp: (_) => setState(() => _pressed = false),
                  onTapCancel: () => setState(() => _pressed = false),
                  onTap: () =>
                      widget.onChanged(widget.selectedIndex == 0 ? 1 : 0),
                  child: AnimatedScale(
                    scale: _pressed ? 0.975 : 1.0,
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOutCubic,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (_hovered)
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  AppGlassRadii.pill,
                                ),
                                color: controls.subtleNeutralOverlay(
                                  hovered: true,
                                  pressed: _pressed,
                                ),
                              ),
                            ),
                          ),
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutBack,
                          left: widget.selectedIndex == 0
                              ? 0
                              : widget.trackWidth - widget.thumbWidth,
                          top: 0,
                          bottom: 0,
                          width: widget.thumbWidth,
                          child: AppGlassSurface(
                            borderRadius: AppGlassRadii.pill,
                            padding: EdgeInsets.zero,
                            tone: AppGlassTone.control,
                            useOwnLayer: false,
                            interactive: true,
                            settingsOverride: appGlassButtonSettingsFor(
                              context,
                            ),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  AppGlassRadii.pill,
                                ),
                                color: Colors.transparent,
                              ),
                              child: Center(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 140),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeOutCubic,
                                  transitionBuilder: (child, animation) {
                                    return FadeTransition(
                                      opacity: animation,
                                      child: ScaleTransition(
                                        scale: Tween<double>(
                                          begin: 0.94,
                                          end: 1,
                                        ).animate(animation),
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: Text(
                                    widget.labels[widget.selectedIndex],
                                    key: ValueKey(widget.selectedIndex),
                                    maxLines: 1,
                                    overflow: TextOverflow.clip,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppGlassIconButtonState extends State<AppGlassIconButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = widget.onPressed != null;
    return AppGlassTooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
        onExit: enabled
            ? (_) => setState(() {
                _hovered = false;
                _pressed = false;
              })
            : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: _pressed ? 0.96 : 1.0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            child: AppGlassRoundControlChrome(
              enabled: enabled,
              hovered: _hovered,
              pressed: _pressed,
              useOwnLayer: widget.useOwnLayer,
              child: Icon(
                widget.icon,
                size: 18,
                color: !enabled
                    ? cs.onSurfaceVariant.withValues(alpha: 0.58)
                    : widget.selected
                    ? cs.primary
                    : cs.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppGlassBadge extends StatelessWidget {
  final int count;
  final bool selected;
  final int maxCount;
  final EdgeInsetsGeometry? margin;

  const AppGlassBadge({
    super.key,
    required this.count,
    this.selected = false,
    this.maxCount = 99,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final controls = appGlassControlPalette(context);
    final displayText = count > maxCount ? '$maxCount+' : count.toString();
    final isWide = displayText.length > 1;
    final foreground = selected ? cs.primary : cs.onSurfaceVariant;
    final fill = selected
        ? controls.activeFill(accentAlpha: 0.05)
        : cs.onSurface.withValues(alpha: 0.05);

    return SelectionContainer.disabled(
      child: AppGlassSurface(
        margin: margin,
        borderRadius: 999,
        padding: EdgeInsets.zero,
        tone: AppGlassTone.control,
        useOwnLayer: false,
        child: Container(
          constraints: BoxConstraints(
            minWidth: isWide ? 22 : 18,
            minHeight: 18,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? 6 : 0,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(999),
          ),
          alignment: Alignment.center,
          child: Text(
            displayText,
            style: TextStyle(
              fontSize: 10,
              height: 1,
              fontWeight: FontWeight.w800,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }
}

class AppGlassButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final String? tooltip;
  final VoidCallback? onPressed;
  final AppGlassButtonRole role;
  final bool expand;
  final double height;

  const AppGlassButton({
    super.key,
    required this.label,
    this.icon,
    this.tooltip,
    this.onPressed,
    this.role = AppGlassButtonRole.secondary,
    this.expand = false,
    this.height = 34,
  });

  @override
  State<AppGlassButton> createState() => _AppGlassButtonState();
}

class _AppGlassButtonState extends State<AppGlassButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final controls = appGlassControlPalette(context);
    final enabled = widget.onPressed != null;
    final foreground = controls.foregroundFor(widget.role);
    final fill = !enabled
        ? controls.disabledFill()
        : _pressed
        ? controls.rolePressedFill(widget.role)
        : _hovered
        ? controls.roleHoverFill(widget.role)
        : controls.roleRestFill(widget.role);
    final content = AppGlassSurface(
      borderRadius: 12,
      padding: EdgeInsets.zero,
      tone: AppGlassTone.control,
      interactive: enabled,
      nativeBackdrop: true,
      staticMaterial: Platform.isMacOS,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        height: widget.height,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
          children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, size: 17, color: foreground),
              const SizedBox(width: 7),
            ],
            Flexible(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: enabled
                      ? foreground
                      : cs.onSurfaceVariant.withValues(alpha: 0.62),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final button = SelectionContainer.disabled(
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
        onExit: enabled
            ? (_) => setState(() {
                _hovered = false;
                _pressed = false;
              })
            : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: _pressed ? 0.985 : 1,
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOutCubic,
            child: widget.expand
                ? SizedBox(width: double.infinity, child: content)
                : content,
          ),
        ),
      ),
    );
    final tooltip = widget.tooltip;
    if (tooltip == null || tooltip.trim().isEmpty) return button;
    return AppGlassTooltip(message: tooltip, child: button);
  }
}

abstract final class MacGlassScrollbarStyle {
  static ScrollbarThemeData articlePaneTheme(BuildContext context) =>
      theme(context, thickness: 8, crossAxisMargin: 1);

  static ScrollbarThemeData theme(
    BuildContext context, {
    double thickness = 5,
    double crossAxisMargin = 4,
    double mainAxisMargin = 4,
  }) {
    final cs = Theme.of(context).colorScheme;
    return ScrollbarThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        final baseAlpha = states.contains(WidgetState.hovered) ? 0.34 : 0.22;
        return cs.onSurface.withValues(alpha: baseAlpha);
      }),
      trackColor: WidgetStateProperty.all(Colors.transparent),
      trackBorderColor: WidgetStateProperty.all(Colors.transparent),
      thickness: WidgetStateProperty.all(thickness),
      radius: const Radius.circular(999),
      crossAxisMargin: crossAxisMargin,
      mainAxisMargin: mainAxisMargin,
    );
  }
}

class MacGlassScrollArea extends StatelessWidget {
  final ScrollController? controller;
  final Widget child;
  final double thickness;
  final double crossAxisMargin;
  final double mainAxisMargin;
  final double gutterWidth;

  const MacGlassScrollArea({
    super.key,
    required this.child,
    this.controller,
    this.thickness = 5,
    this.crossAxisMargin = 4,
    this.mainAxisMargin = 4,
    this.gutterWidth = 14,
  });

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS) return child;
    return ScrollbarTheme(
      data: MacGlassScrollbarStyle.theme(
        context,
        thickness: thickness,
        crossAxisMargin: crossAxisMargin,
        mainAxisMargin: mainAxisMargin,
      ),
      child: Scrollbar(
        controller: controller,
        interactive: false,
        notificationPredicate: (notification) => notification.depth == 0,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: gutterWidth),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: child,
          ),
        ),
      ),
    );
  }
}

class AppGlassTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? initialValue;
  final String label;
  final String? hint;
  final String? helper;
  final Widget? suffixIcon;
  final bool obscureText;
  final int maxLines;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final TextStyle? style;
  final bool monospace;

  const AppGlassTextField({
    super.key,
    this.controller,
    this.initialValue,
    required this.label,
    this.hint,
    this.helper,
    this.suffixIcon,
    this.obscureText = false,
    this.maxLines = 1,
    this.textInputAction,
    this.keyboardType,
    this.inputFormatters,
    this.onChanged,
    this.style,
    this.monospace = false,
  }) : assert(controller == null || initialValue == null);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textStyle =
        style ??
        TextStyle(
          fontSize: maxLines > 1 ? 12 : 14,
          height: maxLines > 1 ? 1.35 : 1.18,
          fontFamily: monospace ? 'monospace' : null,
          fontWeight: maxLines > 1 ? FontWeight.w500 : FontWeight.w600,
          color: cs.onSurface,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppGlassSurface(
          borderRadius: 12,
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
          tone: AppGlassTone.control,
          interactive: true,
          nativeBackdrop: true,
          staticMaterial: Platform.isMacOS,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
              SizedBox(height: maxLines > 1 ? 7 : 3),
              Row(
                crossAxisAlignment: maxLines > 1
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: controller,
                      initialValue: initialValue,
                      obscureText: obscureText,
                      maxLines: obscureText ? 1 : maxLines,
                      minLines: maxLines > 1 ? math.min(5, maxLines) : null,
                      textInputAction: textInputAction,
                      keyboardType: keyboardType,
                      inputFormatters: inputFormatters,
                      onChanged: onChanged,
                      style: textStyle,
                      cursorColor: cs.primary,
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: hint,
                        hintStyle: TextStyle(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.65),
                        ),
                      ),
                    ),
                  ),
                  if (suffixIcon != null) ...[
                    const SizedBox(width: 8),
                    IconTheme(
                      data: IconThemeData(size: 18, color: cs.onSurfaceVariant),
                      child: suffixIcon!,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (helper != null) ...[
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              helper!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ],
    );
  }
}

class _FallbackGlassSurface extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const _FallbackGlassSurface({
    required this.child,
    required this.borderRadius,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.28)),
      ),
      child: child,
    );
  }
}

class _StaticGlassSurface extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final AppGlassTone tone;
  final double borderOpacity;
  final double borderWidth;

  const _StaticGlassSurface({
    required this.child,
    required this.borderRadius,
    required this.tone,
    required this.borderOpacity,
    required this.borderWidth,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderAlpha = switch (tone) {
      AppGlassTone.panel => isDark ? 0.34 : 0.42,
      AppGlassTone.surface => isDark ? 0.28 : 0.36,
      AppGlassTone.control => isDark ? 0.24 : 0.32,
    };
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: cs.onSurfaceVariant.withValues(
            alpha: borderAlpha * borderOpacity.clamp(0.0, 1.0),
          ),
          width: borderWidth,
        ),
      ),
      child: child,
    );
  }
}
