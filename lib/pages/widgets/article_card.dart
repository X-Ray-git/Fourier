import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../common/widgets/app_glass.dart';
import '../../common/widgets/article_card_chrome.dart';
import '../../common/widgets/pill_tag.dart';
import '../../common/widgets/card_press_effect.dart';
import '../../models/article.dart';
import '../../services/article_image_service.dart';
import '../../services/translation_service.dart';
import '../../services/summary_service.dart';
import '../../utils/source_taxonomy.dart';
import 'article_actions_menu.dart';

/// 文章卡片组件
class ArticleCard extends StatefulWidget {
  final ArticleModel article;
  final VoidCallback? onTap;
  final VoidCallback? onTranslate;
  final bool showFeedTitle;
  final bool showSummary;
  final bool isSelected;
  final bool stableTitleWeight;

  const ArticleCard({
    super.key,
    required this.article,
    this.onTap,
    this.onTranslate,
    this.showFeedTitle = true,
    this.showSummary = false,
    this.isSelected = false,
    this.stableTitleWeight = false,
  });

  @override
  State<ArticleCard> createState() => _ArticleCardState();
}

class _ArticleCardState extends State<ArticleCard> {
  late bool _isTranslated;

  @override
  void initState() {
    super.initState();
    _isTranslated = TranslationService.hasTranslation(widget.article.entryId);
  }

  void _onTranslateSuccess() {
    if (mounted) {
      setState(() => _isTranslated = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ArticleCardContent(
      article: widget.article,
      onTap: widget.onTap,
      onTranslate: widget.onTranslate,
      showFeedTitle: widget.showFeedTitle,
      showSummary: widget.showSummary,
      isTranslated: _isTranslated,
      isSelected: widget.isSelected,
      stableTitleWeight: widget.stableTitleWeight,
      onTranslateSuccess: _onTranslateSuccess,
    );
  }
}

class _ArticleCardContent extends StatefulWidget {
  final ArticleModel article;
  final VoidCallback? onTap;
  final VoidCallback? onTranslate;
  final bool showFeedTitle;
  final bool showSummary;
  final bool isTranslated;
  final bool isSelected;
  final bool stableTitleWeight;
  final VoidCallback? onTranslateSuccess;

  const _ArticleCardContent({
    required this.article,
    this.onTap,
    this.onTranslate,
    required this.showFeedTitle,
    required this.showSummary,
    required this.isTranslated,
    required this.isSelected,
    required this.stableTitleWeight,
    this.onTranslateSuccess,
  });

  @override
  State<_ArticleCardContent> createState() => _ArticleCardContentState();
}

class _ArticleCardContentState extends State<_ArticleCardContent> {
  ArticleModel get article => widget.article;
  VoidCallback? get onTap => widget.onTap;
  VoidCallback? get onTranslate => widget.onTranslate;
  bool get showFeedTitle => widget.showFeedTitle;
  bool get showSummary => widget.showSummary;
  bool get isTranslated => widget.isTranslated;
  bool get isSelected => widget.isSelected;
  bool get stableTitleWeight => widget.stableTitleWeight;
  VoidCallback? get onTranslateSuccess => widget.onTranslateSuccess;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final viewLabel = SourceTaxonomy.viewLabelFromCategory(article.category);
    final viewColor = SourceTaxonomy.viewColorFromCategory(article.category);
    final categoryLabel = article.subscriptionCategory.trim();

    return Obx(() {
      final record = TranslationService.recordOf(article.entryId);
      final isPending = record?.isPending ?? false;
      final isTranslated =
          (record?.translatedTitle?.isNotEmpty ?? false) ||
          (record?.translatedContent?.isNotEmpty ?? false);
      final displayTitle = TranslationService.displayTitleFor(article);

      return RepaintBoundary(
        child: Padding(
          padding: ArticleCardChrome.outerPadding,
          child: CardPressEffect(
            onTap: onTap,
            onLongPress: Platform.isMacOS
                ? null
                : () => ArticleActionsMenu.showBottomSheet(
                    context,
                    article: article,
                    onTranslateSuccess: onTranslateSuccess,
                  ),
            onSecondaryTapDown: Platform.isMacOS
                ? (details) {
                    ArticleActionsMenu.showMacOSContextMenu(
                      context,
                      position: details.globalPosition,
                      article: article,
                      onTranslateSuccess: onTranslateSuccess,
                    );
                  }
                : null,
            enableHover: true,
            enablePress: true,
            borderRadius: BorderRadius.circular(ArticleCardChrome.radius),
            child: Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              elevation: 0,
              color: ArticleCardChrome.fillColor(context, selected: isSelected),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ArticleCardChrome.radius),
                side: ArticleCardChrome.borderSide(
                  context,
                  selected: isSelected,
                ),
              ),
              child: Container(
                decoration: article.isRejectedByAi
                    ? BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: colorScheme.primary,
                            width: 4,
                          ),
                        ),
                      )
                    : null,
                padding: ArticleCardChrome.contentPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (article.isRejectedByAi && article.filterReason != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withValues(
                              alpha: 0.4,
                            ),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: colorScheme.primary.withValues(
                                alpha: 0.15,
                              ),
                            ),
                          ),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: Icon(
                                      Icons.auto_awesome,
                                      size: 14,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ),
                                TextSpan(
                                  text: article.filterReason!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                if (!article.isRead)
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: colorScheme.primary,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                  ),
                                TextSpan(
                                  text: displayTitle,
                                  style: TextStyle(
                                    fontSize: ArticleCardChrome.titleFontSize,
                                    height: 1.4,
                                    fontWeight: stableTitleWeight
                                        ? FontWeight.w600
                                        : article.isRead
                                        ? FontWeight.w400
                                        : FontWeight.w600,
                                    color: article.isRead
                                        ? colorScheme.onSurface.withValues(
                                            alpha: 0.7,
                                          )
                                        : colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isPending) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 10,
                                  height: 10,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '翻译中',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else if (isTranslated) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer.withValues(
                                alpha: 0.4,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: AppGlassTooltip(
                              message: '已翻译',
                              child: Icon(
                                Icons.translate,
                                size: 16,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (article.author != null &&
                        article.author!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        article.author!,
                        style: TextStyle(
                          fontSize: ArticleCardChrome.bodyFontSize,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (showSummary)
                      _buildSummaryBlock(colorScheme, article.entryId),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                flex: 0,
                                child: PillTag(
                                  label: viewLabel,
                                  backgroundColor: viewColor.withValues(
                                    alpha: 0.14,
                                  ),
                                  foregroundColor: viewColor,
                                ),
                              ),
                              if (categoryLabel.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Flexible(
                                  flex: 0,
                                  child: PillTag(
                                    label: categoryLabel,
                                    backgroundColor:
                                        colorScheme.surfaceContainerHighest,
                                    foregroundColor:
                                        colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 14,
                              color: colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.6,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatTime(article.publishedAt),
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (showFeedTitle) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _FeedIcon(imageUrl: article.feedImage, size: 14),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              article.feedTitle,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.8,
                                ),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildSummaryBlock(ColorScheme cs, String entryId) {
    final record = SummaryService.recordOf(entryId);
    final status = record?.status;
    final text = record?.summaryText;

    String displayContent;
    Color textColor;
    IconData icon;

    if (status == SummaryStatus.done && text != null && text.isNotEmpty) {
      displayContent = text;
      textColor = cs.onSurfaceVariant.withValues(alpha: 0.8);
      icon = Icons.format_quote_rounded;
    } else if (status == SummaryStatus.pending) {
      displayContent = '摘要生成中…';
      textColor = cs.primary.withValues(alpha: 0.6);
      icon = Icons.sync;
    } else if (status == SummaryStatus.error) {
      displayContent = '摘要生成失败';
      textColor = cs.error.withValues(alpha: 0.6);
      icon = Icons.error_outline;
    } else {
      displayContent = '排队等待摘要…';
      textColor = cs.onSurfaceVariant.withValues(alpha: 0.4);
      icon = Icons.hourglass_empty;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: textColor),
            const SizedBox(width: 4),
            Expanded(
              child:
                  status == SummaryStatus.done &&
                      text != null &&
                      text.isNotEmpty
                  ? Html(
                      data: displayContent,
                      style: {
                        'body': Style(
                          fontSize: FontSize(ArticleCardChrome.bodyFontSize),
                          color: textColor,
                          lineHeight: const LineHeight(1.5),
                          margin: Margins.zero,
                          padding: HtmlPaddings.zero,
                          maxLines: 4,
                          textOverflow: TextOverflow.ellipsis,
                        ),
                        'a': Style(
                          color: cs.primary,
                          textDecoration: TextDecoration.none,
                        ),
                      },
                      onLinkTap: (url, attributes, element) async {
                        if (url != null && url.isNotEmpty) {
                          final uri = Uri.tryParse(url);
                          if (uri != null && await canLaunchUrl(uri)) {
                            await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        }
                      },
                    )
                  : Text(
                      displayContent,
                      style: TextStyle(
                        fontSize: ArticleCardChrome.bodyFontSize,
                        color: textColor,
                        height: 1.5,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatTime(String isoTime) {
    if (isoTime.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoTime);
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inMinutes < 60) {
        return '${diff.inMinutes}分钟前';
      } else if (diff.inHours < 24) {
        return '${diff.inHours}小时前';
      } else if (diff.inDays < 7) {
        return '${diff.inDays}天前';
      } else {
        return DateFormat('MM-dd').format(dt);
      }
    } catch (_) {
      return isoTime;
    }
  }
}

// ─── 订阅源小图标 ─────────────────────────────

class _FeedIcon extends StatelessWidget {
  final String? imageUrl;
  final double size;

  const _FeedIcon({this.imageUrl, this.size = 14});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (imageUrl == null || imageUrl!.isEmpty) {
      return Icon(
        Icons.rss_feed,
        size: size,
        color: cs.onSurfaceVariant.withValues(alpha: 0.6),
      );
    }
    final proxyUrl = ArticleImageService.toProxiedUrl(imageUrl);
    if (proxyUrl == null) {
      return Icon(
        Icons.rss_feed,
        size: size,
        color: cs.onSurfaceVariant.withValues(alpha: 0.6),
      );
    }
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cacheWidth = (size * dpr).round();

    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: CachedNetworkImage(
        imageUrl: proxyUrl,
        httpHeaders: ArticleImageService.httpHeaders,
        width: size,
        height: size,
        memCacheWidth: cacheWidth,
        memCacheHeight: cacheWidth,
        maxWidthDiskCache: cacheWidth * 2,
        maxHeightDiskCache: cacheWidth * 2,
        fit: BoxFit.cover,
        errorWidget: (context, url, error) => Icon(
          Icons.rss_feed,
          size: size,
          color: cs.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
