import 'package:flutter/material.dart';

class MacEmptyPlaceholder extends StatelessWidget {
  final String message;
  final IconData icon;

  const MacEmptyPlaceholder({
    super.key,
    required this.message,
    this.icon = Icons.article_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 48,
              color: cs.primary.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
