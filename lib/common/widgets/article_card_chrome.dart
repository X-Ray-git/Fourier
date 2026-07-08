import 'dart:io';

import 'package:flutter/material.dart';

abstract final class ArticleCardChrome {
  static Color? fillColor(BuildContext context, {required bool selected}) {
    final cs = Theme.of(context).colorScheme;
    if (selected) {
      return cs.primaryContainer.withValues(alpha: 0.5);
    }
    if (!Platform.isMacOS) return null;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return (isDark ? Colors.white : Colors.black).withValues(
      alpha: isDark ? 0.035 : 0.025,
    );
  }

  static BorderSide borderSide(BuildContext context, {required bool selected}) {
    final cs = Theme.of(context).colorScheme;
    if (selected) {
      return BorderSide(color: cs.primary.withValues(alpha: 0.5), width: 1);
    }
    if (Platform.isMacOS) return BorderSide.none;

    return BorderSide(
      color: cs.onSurfaceVariant.withValues(alpha: 0.35),
      width: 1,
    );
  }
}
