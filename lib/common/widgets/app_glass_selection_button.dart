import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../liquid_glass/liquid_glass.dart' as glass;
import 'app_glass.dart';

class AppGlassSelectionOption<T> {
  final T value;
  final String label;
  final IconData icon;

  const AppGlassSelectionOption({
    required this.value,
    required this.label,
    required this.icon,
  });
}

/// A compact macOS glass trigger that morphs into a small selection panel.
///
/// Keep this limited to low-cardinality header choices. Large or scrollable
/// menus should use a conventional popup instead of expanding this surface.
class AppGlassMorphSelectionButton<T> extends StatefulWidget {
  final T value;
  final List<AppGlassSelectionOption<T>> options;
  final String title;
  final IconData titleIcon;
  final String tooltip;
  final ValueChanged<T> onChanged;
  final bool active;
  final bool useOwnLayer;
  final double panelWidth;
  final Color? triggerForegroundColor;
  final IconData? triggerIcon;
  final bool enabled;
  final bool showSelectionIndicator;

  const AppGlassMorphSelectionButton({
    super.key,
    required this.value,
    required this.options,
    required this.title,
    required this.titleIcon,
    required this.tooltip,
    required this.onChanged,
    this.active = false,
    this.useOwnLayer = true,
    this.panelWidth = 188,
    this.triggerForegroundColor,
    this.triggerIcon,
    this.enabled = true,
    this.showSelectionIndicator = true,
  }) : assert(options.length >= 2);

  @override
  State<AppGlassMorphSelectionButton<T>> createState() =>
      _AppGlassMorphSelectionButtonState<T>();
}

class _AppGlassMorphSelectionButtonState<T>
    extends State<AppGlassMorphSelectionButton<T>>
    with SingleTickerProviderStateMixin {
  static const double _buttonSize = 34;
  static const double _optionHeight = 34;
  static const double _panelFixedHeight = 64;
  static const glass.LiquidGlassSettings _panelGlassSettings =
      glass.LiquidGlassSettings(
        blur: 12,
        thickness: 12,
        glassColor: Color.fromRGBO(255, 255, 255, 0.14),
        lightIntensity: 0.68,
        ambientStrength: 0.38,
        saturation: 1.18,
        refractiveIndex: 0.62,
        chromaticAberration: 0.0,
      );

  final _buttonKey = GlobalKey();
  late final glass.GlassMorphController _morphController;
  OverlayEntry? _overlayEntry;
  bool _hovered = false;
  bool _pressed = false;
  bool _isMenuOpen = false;

  double get _panelHeight =>
      _panelFixedHeight + widget.options.length * _optionHeight;

  AppGlassSelectionOption<T> get _selectedOption => widget.options.firstWhere(
    (option) => option.value == widget.value,
    orElse: () => widget.options.first,
  );

  @override
  void initState() {
    super.initState();
    _morphController = glass.GlassMorphController(
      vsync: this,
      speed: glass.MorphSpeed.normal,
    )..addListener(_handleMorphTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _morphController.setDisableAnimations(
      MediaQuery.disableAnimationsOf(context),
    );
  }

  @override
  void didUpdateWidget(covariant AppGlassMorphSelectionButton<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) {
      _hovered = false;
      _pressed = false;
      _removeOverlay(immediate: true);
    }
  }

  @override
  void dispose() {
    _removeOverlay(immediate: true);
    _morphController.dispose();
    super.dispose();
  }

  void _handleMorphTick() {
    _overlayEntry?.markNeedsBuild();
    if (_overlayEntry == null ||
        !_morphController.isClosing ||
        _morphController.isShowing) {
      return;
    }

    final entry = _overlayEntry;
    _overlayEntry = null;
    entry?.remove();
    if (mounted) {
      setState(() => _isMenuOpen = false);
    } else {
      _isMenuOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final option = _selectedOption;
    final highlighted = widget.active || _isMenuOpen;

    return AppGlassTooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: widget.enabled
            ? (_) => setState(() => _hovered = true)
            : null,
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          key: _buttonKey,
          behavior: HitTestBehavior.opaque,
          onTapDown: widget.enabled
              ? (_) => setState(() => _pressed = true)
              : null,
          onTapUp: widget.enabled
              ? (_) => setState(() => _pressed = false)
              : null,
          onTapCancel: widget.enabled
              ? () => setState(() => _pressed = false)
              : null,
          onTap: widget.enabled ? _toggleOverlay : null,
          child: AnimatedScale(
            scale: _pressed ? 0.96 : 1.0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            child: AppGlassRoundControlChrome(
              enabled: widget.enabled,
              hovered: _hovered,
              pressed: _pressed,
              useOwnLayer: widget.useOwnLayer,
              size: _buttonSize,
              child: Icon(
                widget.triggerIcon ?? option.icon,
                size: 18,
                color:
                    widget.triggerForegroundColor ??
                    (highlighted ? cs.primary : cs.onSurface),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _toggleOverlay() {
    if (_overlayEntry != null) {
      _removeOverlay();
      return;
    }
    _showOverlay();
  }

  void _showOverlay() {
    if (!widget.enabled) return;
    final renderObject = _buttonKey.currentContext?.findRenderObject();
    final overlayState = Overlay.of(context);
    final overlayBox = overlayState.context.findRenderObject() as RenderBox?;
    if (renderObject is! RenderBox || overlayBox == null) return;

    final buttonTopLeft = renderObject.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final buttonRight = buttonTopLeft.dx + renderObject.size.width;
    final left = (buttonRight - widget.panelWidth)
        .clamp(
          8.0,
          math.max(8.0, overlayBox.size.width - widget.panelWidth - 8),
        )
        .toDouble();
    final top = buttonTopLeft.dy
        .clamp(8.0, math.max(8.0, overlayBox.size.height - _panelHeight - 8))
        .toDouble();

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeOverlay,
              ),
            ),
            Positioned(
              left: left,
              top: top,
              child: _AppGlassMorphSelectionOverlay<T>(
                morphController: _morphController,
                selected: widget.value,
                showSelectionIndicator: widget.showSelectionIndicator,
                options: widget.options,
                title: widget.title,
                titleIcon: widget.titleIcon,
                panelWidth: widget.panelWidth,
                panelHeight: _panelHeight,
                onClose: _removeOverlay,
                onSelected: (value) {
                  widget.onChanged(value);
                  _removeOverlay();
                },
                collapsedIconColor: widget.triggerForegroundColor,
                collapsedIcon: widget.triggerIcon ?? _selectedOption.icon,
                glassSettings: _panelGlassSettings,
              ),
            ),
          ],
        );
      },
    );
    overlayState.insert(_overlayEntry!);
    setState(() => _isMenuOpen = true);
    _morphController.open();
  }

  void _removeOverlay({bool immediate = false}) {
    final entry = _overlayEntry;
    if (entry == null) return;
    if (immediate) {
      entry.remove();
      _overlayEntry = null;
      _isMenuOpen = false;
      return;
    }

    if (_morphController.isClosing) return;
    _morphController.close();
  }
}

/// A command menu that shares the same anchored liquid-glass morph as the
/// low-cardinality selection controls, without presenting any command as a
/// persistent selected value.
class AppGlassMorphActionButton<T> extends StatelessWidget {
  final List<AppGlassSelectionOption<T>> actions;
  final String title;
  final IconData titleIcon;
  final IconData triggerIcon;
  final String tooltip;
  final ValueChanged<T> onSelected;
  final bool enabled;
  final bool useOwnLayer;
  final double panelWidth;
  final Color? triggerForegroundColor;

  const AppGlassMorphActionButton({
    super.key,
    required this.actions,
    required this.title,
    required this.titleIcon,
    required this.triggerIcon,
    required this.tooltip,
    required this.onSelected,
    this.enabled = true,
    this.useOwnLayer = true,
    this.panelWidth = 188,
    this.triggerForegroundColor,
  }) : assert(actions.length >= 2);

  @override
  Widget build(BuildContext context) {
    return AppGlassMorphSelectionButton<T>(
      value: actions.first.value,
      options: actions,
      title: title,
      titleIcon: titleIcon,
      tooltip: tooltip,
      onChanged: onSelected,
      triggerIcon: triggerIcon,
      enabled: enabled,
      useOwnLayer: useOwnLayer,
      panelWidth: panelWidth,
      triggerForegroundColor: triggerForegroundColor,
      showSelectionIndicator: false,
    );
  }
}

class _AppGlassMorphSelectionOverlay<T> extends StatelessWidget {
  final glass.GlassMorphController morphController;
  final T selected;
  final bool showSelectionIndicator;
  final List<AppGlassSelectionOption<T>> options;
  final String title;
  final IconData titleIcon;
  final ValueChanged<T> onSelected;
  final VoidCallback onClose;
  final double panelWidth;
  final double panelHeight;
  final Color? collapsedIconColor;
  final IconData collapsedIcon;
  final glass.LiquidGlassSettings glassSettings;

  const _AppGlassMorphSelectionOverlay({
    required this.morphController,
    required this.selected,
    required this.showSelectionIndicator,
    required this.options,
    required this.title,
    required this.titleIcon,
    required this.onSelected,
    required this.onClose,
    required this.panelWidth,
    required this.panelHeight,
    required this.collapsedIconColor,
    required this.collapsedIcon,
    required this.glassSettings,
  });

  static const double _buttonSize = 34;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rawValue = morphController.value;
    final effectiveValue =
        morphController.isClosing && morphController.hasHandedOff
        ? 0.0
        : rawValue;
    final clampedValue = effectiveValue.clamp(0.0, 1.0);
    final baseMorphT = morphController.isClosing
        ? _anchoredCloseSettleT(clampedValue)
        : Curves.linearToEaseOut.transform(clampedValue);
    final elasticTail = morphController.isClosing
        ? _anchoredCloseTail(clampedValue)
        : _anchoredOpenTail(clampedValue);
    final morphMin = morphController.isClosing ? -0.014 : 0.0;
    final morphT = (baseMorphT + elasticTail).clamp(morphMin, 1.024);
    final currentWidth = lerpDouble(_buttonSize, panelWidth, morphT)!;
    final currentHeight = lerpDouble(_buttonSize, panelHeight, morphT)!;
    final maxRadius = math.min(currentWidth, currentHeight) / 2;
    final radiusT = Curves.easeOutCubic.transform(morphT.clamp(0.0, 1.0));
    final currentRadius = lerpDouble(maxRadius, 16, radiusT)!;
    final contentOpacity = ((clampedValue - 0.82) / 0.18).clamp(0.0, 1.0);
    final showContent = clampedValue > 0.82 && !morphController.isClosing;
    final showIcon = clampedValue < 0.34;
    final iconOpacity = (1 - clampedValue / 0.34).clamp(0.0, 1.0);

    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: panelWidth,
        height: panelHeight,
        child: glass.LiquidGlassLayer(
          settings: glassSettings,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 0,
                right: 0,
                child: glass.GlassContainer(
                  width: currentWidth,
                  height: currentHeight,
                  useOwnLayer: false,
                  settings: glassSettings,
                  quality: glass.GlassQuality.standard,
                  allowElevation: false,
                  clipBehavior: Clip.antiAlias,
                  shape: glass.LiquidRoundedSuperellipse(
                    borderRadius: currentRadius,
                  ),
                  child: Stack(
                    alignment: Alignment.topRight,
                    children: [
                      if (showIcon)
                        Opacity(
                          opacity: iconOpacity,
                          child: SizedBox(
                            width: _buttonSize,
                            height: _buttonSize,
                            child: Icon(
                              collapsedIcon,
                              size: 18,
                              color: collapsedIconColor ?? cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (showContent)
                        Opacity(
                          opacity: contentOpacity,
                          child: IgnorePointer(
                            ignoring: contentOpacity < 0.95,
                            child: _AppGlassSelectionPanelContent<T>(
                              selected: selected,
                              showSelectionIndicator: showSelectionIndicator,
                              options: options,
                              title: title,
                              titleIcon: titleIcon,
                              panelWidth: panelWidth,
                              panelHeight: panelHeight,
                              onSelected: onSelected,
                              onClose: onClose,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _anchoredOpenTail(double t) {
    const start = 0.42;
    if (t <= start || t >= 1.0) return 0.0;
    final u = ((t - start) / (1.0 - start)).clamp(0.0, 1.0);
    return math.sin(u * math.pi) * 0.028;
  }

  double _anchoredCloseSettleT(double t) {
    final progress = (1.0 - t).clamp(0.0, 1.0);
    const omega = 5.0;
    final settled =
        1.0 - (1.0 + omega * progress) * math.exp(-omega * progress);
    final normalizer = 1.0 - (1.0 + omega) * math.exp(-omega);
    return (1.0 - settled / normalizer).clamp(0.0, 1.0);
  }

  double _anchoredCloseTail(double t) {
    const end = 0.24;
    if (t <= 0.0 || t >= end) return 0.0;
    final u = (t / end).clamp(0.0, 1.0);
    return -math.sin(u * math.pi) * 0.032;
  }
}

class _AppGlassSelectionPanelContent<T> extends StatelessWidget {
  final T selected;
  final bool showSelectionIndicator;
  final List<AppGlassSelectionOption<T>> options;
  final String title;
  final IconData titleIcon;
  final ValueChanged<T> onSelected;
  final VoidCallback onClose;
  final double panelWidth;
  final double panelHeight;

  const _AppGlassSelectionPanelContent({
    required this.selected,
    required this.showSelectionIndicator,
    required this.options,
    required this.title,
    required this.titleIcon,
    required this.onSelected,
    required this.onClose,
    required this.panelWidth,
    required this.panelHeight,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: panelWidth,
      height: panelHeight,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
            child: Row(
              children: [
                Icon(titleIcon, size: 17, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                _AppGlassSelectionCloseButton(onTap: onClose),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.28)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
              child: Column(
                children: [
                  for (final option in options)
                    _AppGlassSelectionOptionRow<T>(
                      option: option,
                      selected:
                          showSelectionIndicator && option.value == selected,
                      onTap: () => onSelected(option.value),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppGlassSelectionOptionRow<T> extends StatefulWidget {
  final AppGlassSelectionOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  const _AppGlassSelectionOptionRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_AppGlassSelectionOptionRow<T>> createState() =>
      _AppGlassSelectionOptionRowState<T>();
}

class _AppGlassSelectionOptionRowState<T>
    extends State<_AppGlassSelectionOptionRow<T>> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final controls = appGlassControlPalette(context);
    final foreground = widget.selected ? cs.primary : cs.onSurface;
    final backgroundColor = controls.optionFill(
      selected: widget.selected,
      hovered: _hovered,
      pressed: _pressed,
    );
    final borderColor = controls.optionBorder(
      selected: widget.selected,
      hovered: _hovered,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: AnimatedScale(
          scale: _pressed ? 0.985 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: _pressed
                ? Duration.zero
                : const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            height: 32,
            margin: const EdgeInsets.symmetric(vertical: 1),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor, width: 0.5),
            ),
            child: Row(
              children: [
                Icon(widget.option.icon, size: 17, color: foreground),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.option.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: widget.selected
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: foreground,
                    ),
                  ),
                ),
                if (widget.selected)
                  Icon(Icons.check_rounded, size: 17, color: cs.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppGlassSelectionCloseButton extends StatefulWidget {
  final VoidCallback onTap;

  const _AppGlassSelectionCloseButton({required this.onTap});

  @override
  State<_AppGlassSelectionCloseButton> createState() =>
      _AppGlassSelectionCloseButtonState();
}

class _AppGlassSelectionCloseButtonState
    extends State<_AppGlassSelectionCloseButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final controls = appGlassControlPalette(context);
    final backgroundColor = controls.neutralOverlay(
      hovered: _hovered,
      pressed: _pressed,
      darkHoverAlpha: 0.09,
      lightHoverAlpha: 0.055,
      darkPressedAlpha: 0.14,
      lightPressedAlpha: 0.08,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: _pressed
                ? Duration.zero
                : const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(
              Icons.keyboard_arrow_up_rounded,
              size: 18,
              color: cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
