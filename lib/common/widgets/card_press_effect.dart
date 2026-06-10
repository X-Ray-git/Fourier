import 'package:flutter/material.dart';

class CardPressEffect extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(TapDownDetails)? onSecondaryTapDown;
  final bool enableHover;
  final bool enablePress;
  final BorderRadiusGeometry borderRadius;

  const CardPressEffect({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapDown,
    this.enableHover = true,
    this.enablePress = true,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  State<CardPressEffect> createState() => _CardPressEffectState();
}

class _CardPressEffectState extends State<CardPressEffect> {
  bool _isHovering = false;
  Offset _hoverPosition = Offset.zero;
  bool _isPressed = false;
  Offset _pressPosition = Offset.zero;

  static const _pressInDuration = Duration(milliseconds: 80);
  static const _pressOutDuration = Duration(milliseconds: 350);

  void _onTapDown(TapDownDetails d) {
    if (!widget.enablePress) return;
    setState(() {
      _isPressed = true;
      _pressPosition = d.localPosition;
    });
  }

  void _onTapUp(TapUpDetails d) {
    if (!widget.enablePress) return;
    setState(() => _isPressed = false);
  }

  void _onTapCancel() {
    if (!widget.enablePress) return;
    setState(() => _isPressed = false);
  }

  void _onHover(dynamic event) {
    if (!widget.enableHover) return;
    setState(() {
      _hoverPosition = event.localPosition as Offset;
    });
  }

  void _onEnter(dynamic event) {
    if (!widget.enableHover) return;
    setState(() {
      _isHovering = true;
      _hoverPosition = event.localPosition as Offset;
    });
  }

  void _onExit(dynamic event) {
    if (!widget.enableHover) return;
    setState(() => _isHovering = false);
  }

  bool get _showEffect => _isPressed && widget.enablePress;
  bool get _showHover => _isHovering && !_showEffect && widget.enableHover;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final highlightColor =
        brightness == Brightness.dark ? Colors.white : Colors.black;

    return TweenAnimationBuilder<double>(
      tween: Tween(
        begin: _showEffect ? 1.0 : 0.985,
        end: _showEffect ? 0.985 : 1.0,
      ),
      duration: _showEffect ? _pressInDuration : _pressOutDuration,
      curve: _showEffect ? Curves.easeOut : Curves.easeOutCubic,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: MouseRegion(
        onHover: _onHover,
        onEnter: _onEnter,
        onExit: _onExit,
        child: GestureDetector(
          onTapDown: _onTapDown,
          onTapUp: _onTapUp,
          onTapCancel: _onTapCancel,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onSecondaryTapDown: widget.onSecondaryTapDown,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: [
              widget.child,
              if (_showHover || _showEffect)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ClipRRect(
                      borderRadius: widget.borderRadius,
                      child: CustomPaint(
                        painter: _GlassHighlightPainter(
                          position: _showEffect ? _pressPosition : _hoverPosition,
                          color: highlightColor,
                          alpha: _showEffect ? 0.06 : 0.05,
                        ),
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

class _GlassHighlightPainter extends CustomPainter {
  final Offset position;
  final Color color;
  final double alpha;

  const _GlassHighlightPainter({
    required this.position,
    required this.color,
    required this.alpha,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color.withValues(alpha: alpha), Colors.transparent],
        stops: const [0.0, 1.0],
        radius: 0.7,
      ).createShader(
        Rect.fromCircle(center: position, radius: size.width * 0.7),
      );
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_GlassHighlightPainter old) =>
      position != old.position || color != old.color || alpha != old.alpha;
}
