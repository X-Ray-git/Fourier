import 'dart:async';

import 'package:flutter/material.dart';

import '../../../common/widgets/diagnostic_activity_marker.dart';
import '../../../services/animation_activity_monitor.dart';

/// Stops animating without presenting a frozen progress ring as download progress.
class ImageLoadingPlaceholder extends StatefulWidget {
  const ImageLoadingPlaceholder({
    super.key,
    required this.size,
    required this.strokeWidth,
  });

  final double size;
  final double strokeWidth;

  @override
  State<ImageLoadingPlaceholder> createState() =>
      _ImageLoadingPlaceholderState();
}

class _ImageLoadingPlaceholderState extends State<ImageLoadingPlaceholder> {
  Timer? _timer;
  bool _animated = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _animated = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DiagnosticActivityMarker(
      kind: AnimationActivityKind.imagePlaceholder,
      active: _animated,
      child: _animated
          ? SizedBox(
              width: widget.size,
              height: widget.size,
              child: CircularProgressIndicator(strokeWidth: widget.strokeWidth),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final icon = Icon(
                  Icons.image_outlined,
                  size: widget.size,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                );
                if (constraints.maxHeight < 48 || constraints.maxWidth < 100) {
                  return Tooltip(message: '等待图片加载', child: icon);
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon,
                    const SizedBox(height: 6),
                    Text(
                      '等待图片加载',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
