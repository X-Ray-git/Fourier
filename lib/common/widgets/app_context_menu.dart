import 'dart:io';

import 'package:flutter/material.dart';

sealed class AppContextMenuEntry<T> {
  const AppContextMenuEntry();
}

class AppContextMenuAction<T> extends AppContextMenuEntry<T> {
  final T value;
  final IconData icon;
  final String label;
  final bool enabled;
  final bool loading;
  final bool destructive;
  final Color? color;

  const AppContextMenuAction({
    required this.value,
    required this.icon,
    required this.label,
    this.enabled = true,
    this.loading = false,
    this.destructive = false,
    this.color,
  });
}

class AppContextMenuDivider<T> extends AppContextMenuEntry<T> {
  const AppContextMenuDivider();
}

abstract final class AppContextMenu {
  static Future<T?> show<T>(
    BuildContext context, {
    required Offset position,
    required List<AppContextMenuEntry<T>> entries,
    double minWidth = 176,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isMacOS = Platform.isMacOS;
    final background = isMacOS
        ? Color.alphaBlend(
            cs.surfaceContainerHighest.withValues(alpha: 0.90),
            cs.surface,
          )
        : cs.surfaceContainerHighest;

    return showMenu<T>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: background,
      elevation: isMacOS ? 10 : 6,
      shadowColor: Colors.black.withValues(alpha: isMacOS ? 0.24 : 0.18),
      surfaceTintColor: Colors.transparent,
      items: entries.map((entry) {
        return switch (entry) {
          AppContextMenuAction<T>() => _actionEntry(
            context,
            entry,
            minWidth: minWidth,
          ),
          AppContextMenuDivider<T>() => const PopupMenuDivider(height: 8),
        };
      }).toList(),
    );
  }

  static PopupMenuEntry<T> _actionEntry<T>(
    BuildContext context,
    AppContextMenuAction<T> action, {
    required double minWidth,
  }) {
    return PopupMenuItem<T>(
      value: action.value,
      enabled: action.enabled && !action.loading,
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: minWidth),
        child: _AppContextMenuActionRow(action: action),
      ),
    );
  }
}

class _AppContextMenuActionRow<T> extends StatelessWidget {
  final AppContextMenuAction<T> action;

  const _AppContextMenuActionRow({required this.action});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = action.enabled && !action.loading;
    final baseColor = action.destructive
        ? cs.error
        : (action.color ?? cs.onSurface);
    final foreground = enabled
        ? baseColor
        : cs.onSurfaceVariant.withValues(alpha: 0.56);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: Center(
            child: action.loading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: baseColor,
                    ),
                  )
                : Icon(action.icon, size: 18, color: foreground),
          ),
        ),
        const SizedBox(width: 9),
        Flexible(
          child: Text(
            action.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
        ),
      ],
    );
  }
}
