import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../liquid_glass/liquid_glass.dart';
import 'continuous_rectangle.dart';

enum AppGlassTone { surface, panel, control }

enum AppGlassButtonRole { primary, secondary, destructive }

enum AppGlassTooltipPlacement { bottom, right }

Color appGlassActiveControlFill(
  BuildContext context, {
  double accentAlpha = 0.05,
}) {
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final neutralBase = (isDark ? Colors.black : cs.scrim).withValues(
    alpha: isDark ? 0.22 : 0.13,
  );
  return Color.alphaBlend(
    cs.primary.withValues(alpha: accentAlpha),
    neutralBase,
  );
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
    this.staticMaterial = false,
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

    if (staticMaterial) {
      return _StaticGlassSurface(
        borderRadius: borderRadius,
        padding: padding,
        margin: margin,
        tone: tone,
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
          position: DecorationPosition.foreground,
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
  final LayerLink _link = LayerLink();
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
    final placement = _tooltipPlacement(widget.placement);
    _entry = OverlayEntry(
      builder: (context) => Theme(
        data: theme,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScale),
          child: Positioned.fill(
            child: IgnorePointer(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CompositedTransformFollower(
                    link: _link,
                    showWhenUnlinked: false,
                    targetAnchor: placement.targetAnchor,
                    followerAnchor: placement.followerAnchor,
                    offset: placement.offset,
                    child: _AppGlassTooltipBubble(
                      message: widget.message,
                      scaleAlignment: placement.scaleAlignment,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_entry!);
  }

  _AppGlassTooltipPlacementData _tooltipPlacement(
    AppGlassTooltipPlacement placement,
  ) {
    return switch (placement) {
      AppGlassTooltipPlacement.bottom => const _AppGlassTooltipPlacementData(
        targetAnchor: Alignment.bottomCenter,
        followerAnchor: Alignment.topCenter,
        offset: Offset(0, 9),
        scaleAlignment: Alignment.topCenter,
      ),
      AppGlassTooltipPlacement.right => const _AppGlassTooltipPlacementData(
        targetAnchor: Alignment.centerRight,
        followerAnchor: Alignment.centerLeft,
        offset: Offset(9, 0),
        scaleAlignment: Alignment.centerLeft,
      ),
    };
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
        onEnter: (_) => _scheduleTooltip(),
        onExit: (_) => _hideTooltip(),
        child: CompositedTransformTarget(link: _link, child: widget.child),
      ),
    );
  }
}

class _AppGlassTooltipPlacementData {
  final Alignment targetAnchor;
  final Alignment followerAnchor;
  final Offset offset;
  final Alignment scaleAlignment;

  const _AppGlassTooltipPlacementData({
    required this.targetAnchor,
    required this.followerAnchor,
    required this.offset,
    required this.scaleAlignment,
  });
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
            constraints: const BoxConstraints(maxWidth: 260),
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
  final double selectedFillOpacity;
  final bool useOwnLayer;

  const AppGlassIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.selected = false,
    this.selectedFillOpacity = 0.16,
    this.useOwnLayer = true,
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
    final selectedFill = appGlassActiveControlFill(
      context,
      accentAlpha: widget.selectedFillOpacity,
    );
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
            child: AppGlassSurface(
              borderRadius: 999,
              padding: EdgeInsets.zero,
              tone: AppGlassTone.control,
              interactive: enabled,
              useOwnLayer: widget.useOwnLayer,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: widget.selected
                      ? selectedFill
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
    final displayText = count > maxCount ? '$maxCount+' : count.toString();
    final isWide = displayText.length > 1;
    final foreground = selected ? cs.primary : cs.onSurfaceVariant;
    final fill = selected
        ? appGlassActiveControlFill(context, accentAlpha: 0.05)
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
    final enabled = widget.onPressed != null;
    final foreground = switch (widget.role) {
      AppGlassButtonRole.primary => cs.primary,
      AppGlassButtonRole.secondary => cs.onSurface,
      AppGlassButtonRole.destructive => cs.error,
    };
    final selectedFill = switch (widget.role) {
      AppGlassButtonRole.primary => appGlassActiveControlFill(
        context,
        accentAlpha: 0.06,
      ),
      AppGlassButtonRole.destructive => Color.alphaBlend(
        cs.error.withValues(alpha: 0.05),
        cs.scrim.withValues(alpha: 0.18),
      ),
      AppGlassButtonRole.secondary => cs.onSurface.withValues(alpha: 0.03),
    };
    final hoverFill = switch (widget.role) {
      AppGlassButtonRole.primary => appGlassActiveControlFill(
        context,
        accentAlpha: 0.065,
      ),
      AppGlassButtonRole.destructive => cs.error.withValues(alpha: 0.045),
      AppGlassButtonRole.secondary => cs.onSurface.withValues(alpha: 0.035),
    };
    final fill = !enabled
        ? cs.onSurface.withValues(alpha: 0.03)
        : _pressed
        ? hoverFill.withValues(alpha: (hoverFill.a * 1.2).clamp(0.0, 1.0))
        : _hovered
        ? hoverFill
        : selectedFill;
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
    final cs = Theme.of(context).colorScheme;
    return ScrollbarTheme(
      data: ScrollbarThemeData(
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

  const _StaticGlassSurface({
    required this.child,
    required this.borderRadius,
    required this.tone,
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
          color: cs.onSurfaceVariant.withValues(alpha: borderAlpha),
          width: 0.75,
        ),
      ),
      child: child,
    );
  }
}
