import 'package:flutter/material.dart';

class MacEmptyPlaceholder extends StatelessWidget {
  final String? message;
  final IconData icon;

  const MacEmptyPlaceholder({
    super.key,
    this.message,
    this.icon = Icons.article_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Icon(
        icon,
        size: 48,
        color: cs.onSurfaceVariant.withValues(alpha: 0.15),
      ),
    );
  }
}
