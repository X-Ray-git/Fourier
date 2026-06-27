import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../liquid_glass/liquid_glass.dart';
import 'continuous_rectangle.dart';

enum AppGlassTone { surface, panel, control }

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

  const AppGlassSurface({
    super.key,
    required this.child,
    this.borderRadius = 18,
    this.padding,
    this.margin,
    this.tone = AppGlassTone.surface,
    this.interactive = false,
    this.useOwnLayer = true,
    this.clipBehavior = Clip.antiAlias,
    this.nativeBackdrop = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!Platform.isMacOS) {
      return _FallbackGlassSurface(
        borderRadius: borderRadius,
        padding: padding,
        margin: margin,
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

    final settings = _settingsFor(tone, isDark);
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
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: isDark ? 0.22 : 0.32),
              width: 0.5,
            ),
          ),
          child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
        ),
      ),
    );
  }

  LiquidGlassSettings _settingsFor(AppGlassTone tone, bool isDark) {
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
    final baseTint = Color.lerp(
      cs.surfaceContainerHighest,
      cs.scrim,
      isDark ? 0.18 : 0.10,
    )!;
    final topTint = Color.lerp(baseTint, cs.onSurface, isDark ? 0.10 : 0.05)!;
    final bottomTint = Color.lerp(baseTint, cs.scrim, isDark ? 0.22 : 0.14)!;
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
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      topTint.withValues(alpha: isDark ? 0.30 : 0.24),
                      baseTint.withValues(alpha: isDark ? 0.24 : 0.18),
                      bottomTint.withValues(alpha: isDark ? 0.28 : 0.22),
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
      color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.08),
      blurRadius: 18,
      offset: const Offset(0, 6),
    );
    _drawShadow(
      canvas,
      path,
      color: Colors.black.withValues(alpha: isDark ? 0.14 : 0.04),
      blurRadius: 3,
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
        ..blendMode = BlendMode.overlay
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = shader
        ..blendMode = BlendMode.overlay
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = shader
        ..blendMode = BlendMode.overlay
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
    this.borderRadius = 20,
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

class AppGlassIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  const AppGlassIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.selected = false,
  });

  @override
  State<AppGlassIconButton> createState() => _AppGlassIconButtonState();
}

class _AppGlassIconButtonState extends State<AppGlassIconButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = widget.onPressed != null;
    return Tooltip(
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
            child: AppGlassSurface(
              borderRadius: 999,
              padding: EdgeInsets.zero,
              tone: AppGlassTone.control,
              interactive: enabled,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: widget.selected
                      ? cs.primary.withValues(alpha: 0.16)
                      : _hovered
                      ? cs.onSurface.withValues(alpha: 0.06)
                      : Colors.transparent,
                ),
                child: Icon(
                  widget.icon,
                  size: 18,
                  color: widget.selected ? cs.primary : cs.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
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
