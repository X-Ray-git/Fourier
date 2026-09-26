import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

import '../../../services/external_link_service.dart';
import '../../../utils/selectable_html_compatibility.dart';
import 'stable_selectable_html.dart';

/// Shared reader information styling; callers own visibility and data loading.
/// Uses the reader's surrounding SelectionArea, like the article summary.
class ArticleInfoCard extends StatelessWidget {
  const ArticleInfoCard({
    super.key,
    required this.title,
    required this.icon,
    required String this.text,
    this.foregroundColor,
    this.backgroundColor,
  }) : child = null;

  /// Reuses the same title, surface and spacing for structured reader content.
  const ArticleInfoCard.content({
    super.key,
    required this.title,
    required this.icon,
    required Widget this.child,
    this.foregroundColor,
    this.backgroundColor,
  }) : text = null;

  final String title;
  final IconData icon;
  final String? text;
  final Widget? child;
  final Color? foregroundColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.light
              ? (backgroundColor ??
                        Theme.of(context).colorScheme.secondaryContainer)
                    .withValues(alpha: 0.10)
              : (backgroundColor ??
                        Theme.of(context).colorScheme.secondaryContainer)
                    .withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color:
                      foregroundColor ??
                      Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color:
                        foregroundColor ??
                        Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            child ??
                StableSelectableHtml(
                  data: SelectableHtmlCompatibility.normalizePlainText(text!),
                  renderConfigurationKey: Object.hash(
                    Theme.of(context).brightness,
                    Theme.of(context).colorScheme.primary,
                  ),
                  style: {
                    // Html 会把 block wrapper 转为 WidgetSpan；与外层
                    // SelectionArea 组合时必须让根节点和摘要文本保持同一流。
                    'html': Style(display: Display.inline),
                    'body': Style(
                      display: Display.inline,
                      fontSize: FontSize(14),
                      lineHeight: const LineHeight(1.5),
                      margin: Margins.zero,
                      padding: HtmlPaddings.zero,
                    ),
                    'div': Style(display: Display.inline),
                    'p': Style(
                      display: Display.inline,
                      margin: Margins.zero,
                      padding: HtmlPaddings.zero,
                    ),
                    'a': Style(
                      color: Theme.of(context).colorScheme.primary,
                      textDecoration: TextDecoration.none,
                    ),
                  },
                  onLinkTap: (url, attributes, element) async {
                    if (url != null && url.isNotEmpty) {
                      await ExternalLinkService.openUrlWithFeedback(url);
                    }
                  },
                ),
          ],
        ),
      ),
    );
  }
}
