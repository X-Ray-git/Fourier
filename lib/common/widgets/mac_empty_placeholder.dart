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

class MacSplitDetailEmptyPlaceholder extends StatelessWidget {
  final IconData icon;
  final double topInset;
  final FocusNode? focusNode;

  const MacSplitDetailEmptyPlaceholder({
    super.key,
    this.icon = Icons.article_outlined,
    this.topInset = kToolbarHeight,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        SizedBox(height: topInset),
        Expanded(child: MacEmptyPlaceholder(icon: icon)),
      ],
    );
    final node = focusNode;
    if (node == null) return content;
    return Focus(focusNode: node, skipTraversal: true, child: content);
  }
}
