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
    return AppGlassTooltip(
      message: syncing ? widget.syncingTooltip : widget.idleTooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: syncing ? null : widget.onPressed,
        child: MouseRegion(
          cursor: syncing ? MouseCursor.defer : SystemMouseCursors.click,
          child: AppGlassSurface(
            borderRadius: 999,
            padding: EdgeInsets.zero,
            tone: AppGlassTone.control,
            nativeBackdrop: true,
            interactive: !syncing,
            child: SizedBox(
              width: 34,
              height: 34,
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
                          : (widget.idleColor ?? cs.onSurfaceVariant),
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
