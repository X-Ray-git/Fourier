import 'package:flutter/material.dart';

Path continuousRectanglePath(Rect rect, double radius) {
  return RoundedSuperellipseBorder(
    borderRadius: BorderRadius.all(Radius.circular(radius)),
  ).getOuterPath(rect);
}

class ContinuousRectangleClipper extends CustomClipper<Path> {
  final double radius;

  const ContinuousRectangleClipper(this.radius);

  @override
  Path getClip(Size size) {
    return continuousRectanglePath(Offset.zero & size, radius);
  }

  @override
  bool shouldReclip(covariant ContinuousRectangleClipper oldClipper) {
    return radius != oldClipper.radius;
  }
}

class ContinuousRectangleClip extends StatelessWidget {
  final double radius;
  final Clip clipBehavior;
  final Widget child;

  const ContinuousRectangleClip({
    super.key,
    required this.radius,
    this.clipBehavior = Clip.antiAlias,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: ContinuousRectangleClipper(radius),
      clipBehavior: clipBehavior,
      child: child,
    );
  }
}
