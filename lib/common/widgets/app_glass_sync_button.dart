import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_glass.dart';

class AppGlassSyncButton extends StatefulWidget {
  final bool syncing;
  final VoidCallback? onPressed;
  final String idleTooltip;
  final String syncingTooltip;
  final Color? idleColor;
  final Color? syncingColor;

  const AppGlassSyncButton({
    super.key,
    required this.syncing,
    required this.onPressed,
    this.idleTooltip = '同步',
    this.syncingTooltip = '同步中',
    this.idleColor,
    this.syncingColor,
  });

  @override
  State<AppGlassSyncButton> createState() => _AppGlassSyncButtonState();
}

class _AppGlassSyncButtonState extends State<AppGlassSyncButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinController;
  bool _hovered = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _syncSpinAnimation(widget.syncing);
  }

  @override
  void didUpdateWidget(covariant AppGlassSyncButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.syncing != widget.syncing) {
      _syncSpinAnimation(widget.syncing);
    }
  }

  void _syncSpinAnimation(bool syncing) {
    if (syncing) {
      if (!_spinController.isAnimating) {
        unawaited(_spinController.repeat());
      }
      return;
    }

    _spinController.stop();
    _spinController.reset();
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final syncing = widget.syncing;
    final enabled = !syncing && widget.onPressed != null;
    return AppGlassTooltip(
      message: syncing ? widget.syncingTooltip : widget.idleTooltip,
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
          onTap: enabled ? widget.onPressed : null,
          child: AnimatedScale(
            scale: _pressed ? 0.96 : 1.0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            child: AppGlassRoundControlChrome(
              enabled: enabled,
              hovered: _hovered,
              pressed: _pressed,
              child: Center(
                child: RotationTransition(
                  turns: _spinController,
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.rotationY(math.pi),
                    child: Icon(
                      Icons.sync,
                      size: 18,
                      color: syncing
                          ? (widget.syncingColor ?? cs.primary)
                          : (widget.idleColor ?? cs.onSurface),
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
