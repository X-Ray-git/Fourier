import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Informational overlay: it must never steal hover, clicks or scrolling from
/// the link underneath, including when it appears directly under the pointer.
class ArticleLinkPreview extends StatelessWidget {
  const ArticleLinkPreview({super.key, required this.url});

  final ValueListenable<String?> url;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: ValueListenableBuilder<String?>(
        valueListenable: url,
        builder: (context, value, child) {
          if (value == null || value.isEmpty) return const SizedBox.shrink();
          return Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              border: Border(top: BorderSide(color: colors.outlineVariant)),
            ),
            child: Row(
              children: [
                Icon(Icons.link, size: 13, color: colors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
