import 'dart:io';

import 'package:flutter/material.dart';

abstract final class ArticleCardChrome {
  static double get radius => Platform.isMacOS ? 10 : 16;
  static double get titleFontSize => Platform.isMacOS ? 14 : 16;
  static double get bodyFontSize => Platform.isMacOS ? 12 : 13;

  static EdgeInsets get outerPadding => EdgeInsets.symmetric(
    horizontal: Platform.isMacOS ? 8 : 12,
    vertical: Platform.isMacOS ? 4 : 6,
  );

  static EdgeInsets get contentPadding =>
      EdgeInsets.all(Platform.isMacOS ? 12 : 16);

  static Color? fillColor(BuildContext context, {required bool selected}) {
    final cs = Theme.of(context).colorScheme;
    if (selected) {
      return cs.primaryContainer.withValues(alpha: 0.5);
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return (isDark ? Colors.white : Colors.black).withValues(
      alpha: Platform.isMacOS
          ? (isDark ? 0.018 : 0.012)
          : (isDark ? 0.035 : 0.022),
    );
  }

  static BorderSide borderSide(BuildContext context, {required bool selected}) {
    final cs = Theme.of(context).colorScheme;
    if (selected) {
      return BorderSide(color: cs.primary.withValues(alpha: 0.5), width: 1);
    }
    return BorderSide.none;
  }
}

abstract final class MacArticleListChrome {
  static const EdgeInsets viewportPadding = EdgeInsets.only(bottom: 8);

  static EdgeInsets contentPadding(BuildContext context) => EdgeInsets.only(
    right: 2,
    bottom: 8 + MediaQuery.paddingOf(context).bottom,
  );
}
