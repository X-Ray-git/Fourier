import 'package:flutter/material.dart';
import '../../src/renderer/liquid_glass_renderer.dart';
import '../../types/glass_quality.dart';
import 'glass_card.dart';
import 'glass_list_tile.dart';

/// A convenience wrapper that groups [GlassListTile]s inside a [GlassCard].
///
/// [GlassGroupedSection] automatically applies `isLast: true` to the final
/// tile, suppressing its bottom divider — the most common source of bugs when
/// building grouped list sections manually.
///
/// ## iOS 26 pattern
///
/// In iOS 26, Settings-style screens group related rows inside
/// `UITableView` grouped sections. [GlassGroupedSection] provides the
/// glass equivalent of that pattern.
///
/// ## Usage
///
/// ```dart
/// GlassGroupedSection(
///   header: Text('Network', style: TextStyle(color: CupertinoColors.white.withOpacity(0.7))),
///   children: [
///     GlassListTile(
///       leading: Icon(CupertinoIcons.wifi, color: CupertinoColors.white),
///       title: Text('Wi-Fi'),
///       trailing: GlassListTile.chevron,
///     ),
///     GlassListTile(
///       leading: Icon(CupertinoIcons.bluetooth, color: CupertinoColors.white),
///       title: Text('Bluetooth'),
///       trailing: GlassListTile.chevron,
///     ),
///     GlassListTile(
///       leading: Icon(CupertinoIcons.antenna_radiowaves_left_right,
///           color: CupertinoColors.white),
///       title: Text('VPN'),
///       trailing: GlassListTile.chevron,
///       // No need to set isLast — GlassGroupedSection handles it.
///     ),
///   ],
/// )
/// ```
///
/// ## With a section header
///
/// ```dart
/// GlassGroupedSection(
///   header: Padding(
///     padding: EdgeInsets.only(left: 16, bottom: 8),
///     child: Text(
///       'GENERAL',
///       style: TextStyle(
///         color: CupertinoColors.white.withOpacity(0.54),
///         fontSize: 13,
///         fontWeight: FontWeight.w600,
///         letterSpacing: 0.5,
///       ),
///     ),
///   ),
///   children: [ ... ],
/// )
/// ```
class GlassGroupedSection extends StatelessWidget {
  /// Creates a grouped section of glass list tiles.
  const GlassGroupedSection({
    super.key,
    required this.children,
    this.header,
    this.footer,
    this.margin,
    this.shape,
    this.settings,
    this.useOwnLayer = false,
    this.quality,
  });

  /// The list tiles to display inside the section.
  ///
  /// Typically [GlassListTile] widgets. The last child automatically gets
  /// `isLast: true` applied to suppress its bottom divider.
  final List<Widget> children;

  /// Optional header displayed above the glass card.
  ///
  /// Typically a [Text] widget with section title styling (uppercase, small
  /// font, muted colour) matching iOS grouped table section headers.
  final Widget? header;

  /// Optional footer displayed below the glass card.
  ///
  /// Typically a [Text] widget with explanatory text matching iOS grouped
  /// table section footers.
  final Widget? footer;

  /// Empty space to surround the section card.
  ///
  /// Defaults to `EdgeInsets.symmetric(horizontal: 16, vertical: 6)` matching
  /// iOS grouped table section insets.
  final EdgeInsetsGeometry? margin;

  /// Shape of the glass card.
  ///
  /// If null, uses [GlassCard]'s default shape.
  final LiquidShape? shape;

  /// Glass effect settings.
  ///
  /// If null, inherits from the parent layer or theme.
  final LiquidGlassSettings? settings;

  /// Whether to create its own glass layer.
  ///
  /// Defaults to false (grouped mode).
  final bool useOwnLayer;

  /// Rendering quality.
  final GlassQuality? quality;
  @override
  Widget build(BuildContext context) {
    final effectiveMargin =
        margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 6);
    // Clone the children list, applying isLast to the final GlassListTile.
    final processedChildren = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      final isLast = i == children.length - 1;
      if (isLast && child is GlassListTile) {
        // Rebuild the tile with isLast: true by wrapping in a builder that
        // creates a new GlassListTile with the same properties + isLast.
        processedChildren.add(_LastTileWrapper(key: child.key, child: child));
      } else {
        processedChildren.add(child);
      }
    }
    final card = GlassCard(
      padding: EdgeInsets.zero,
      margin: effectiveMargin,
      shape: shape ?? const LiquidRoundedSuperellipse(borderRadius: 12),
      settings: settings,
      useOwnLayer: useOwnLayer,
      quality: quality,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: processedChildren,
      ),
    );
    if (header == null && footer == null) return card;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [?header, card, ?footer],
    );
  }
}

/// Internal widget that wraps the last [GlassListTile] to force `isLast: true`
/// and `showDivider: false` without requiring the user to specify it.
class _LastTileWrapper extends StatelessWidget {
  const _LastTileWrapper({super.key, required this.child});
  final GlassListTile child;
  @override
  Widget build(BuildContext context) {
    // Re-create the tile with isLast semantics applied.
    // This preserves all user-provided properties while ensuring the last
    // tile in a section never renders a bottom divider.
    return GlassListTile(
      key: child.key,
      leading: child.leading,
      title: child.title,
      subtitle: child.subtitle,
      trailing: child.trailing,
      onTap: child.onTap,
      onLongPress: child.onLongPress,
      isLast: true,
      contentPadding: child.contentPadding,
      leadingIconColor: child.leadingIconColor,
      titleStyle: child.titleStyle,
      subtitleStyle: child.subtitleStyle,
      showDivider: false,
      dividerIndent: child.dividerIndent,
    );
  }
}
