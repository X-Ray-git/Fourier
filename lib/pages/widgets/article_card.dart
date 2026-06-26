import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../common/widgets/feedback_toast.dart';
import '../../common/widgets/pill_tag.dart';
import '../../common/widgets/card_press_effect.dart';
import '../../models/article.dart';
import '../../services/article_image_service.dart';
import '../../services/translation_service.dart';
import '../../services/summary_service.dart';
import '../../utils/source_taxonomy.dart';

/// 文章卡片组件
class ArticleCard extends StatefulWidget {
  final ArticleModel article;
  final VoidCallback? onTap;
  final VoidCallback? onTranslate;
  final bool showFeedTitle;
  final bool showSummary;
  final bool isSelected;

  const ArticleCard({
    super.key,
    required this.article,
    this.onTap,
    this.onTranslate,
    this.showFeedTitle = true,
    this.showSummary = false,
    this.isSelected = false,
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
  final VoidCallback? onTranslateSuccess;

  const _ArticleCardContent({
    required this.article,
    this.onTap,
    this.onTranslate,
    required this.showFeedTitle,
    required this.showSummary,
    required this.isTranslated,
    required this.isSelected,
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
      final summaryRecord = SummaryService.recordOf(article.entryId);
      final isSummaryPending = summaryRecord?.isPending ?? false;
      final hasSummary =
          (summaryRecord?.isSummarized ?? false) &&
          (summaryRecord?.summaryText?.trim().isNotEmpty ?? false);
      final displayTitle = TranslationService.displayTitleFor(article);

      return RepaintBoundary(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: Platform.isMacOS ? 8 : 12,
            vertical: Platform.isMacOS ? 2 : 6,
          ),
          child: CardPressEffect(
            onTap: onTap,
            onLongPress: Platform.isMacOS
                ? null
                : () => _showAiActionsMenu(
                    context,
                    isTranslated: isTranslated,
                    isTranslationPending: isPending,
                    hasSummary: hasSummary,
                    isSummaryPending: isSummaryPending,
                  ),
            onSecondaryTapDown: Platform.isMacOS
                ? (details) {
                    _showMacOSContextMenu(
                      context,
                      details.globalPosition,
                      isTranslated: isTranslated,
                      isTranslationPending: isPending,
                      hasSummary: hasSummary,
                      isSummaryPending: isSummaryPending,
                    );
                  }
                : null,
            enableHover: true,
            enablePress: true,
            borderRadius: BorderRadius.circular(Platform.isMacOS ? 8 : 16),
            child: Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              elevation: 0,
              color: isSelected
                  ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                  : (Platform.isMacOS ? Colors.transparent : null),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Platform.isMacOS ? 8 : 16),
                side: Platform.isMacOS && !isSelected
                    ? BorderSide.none
                    : BorderSide(
                        color: isSelected
                            ? colorScheme.primary.withValues(alpha: 0.5)
                            : colorScheme.outlineVariant.withValues(
                                alpha: 0.35,
                              ),
                        width: 1,
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
                padding: EdgeInsets.all(Platform.isMacOS ? 12 : 16),
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
                                    fontSize: 16,
                                    height: 1.4,
                                    fontWeight: article.isRead
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
                            child: Tooltip(
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
                          fontSize: 13,
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
                          fontSize: FontSize(13),
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
                        fontSize: 13,
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

  Future<void> _translateArticle() async {
    try {
      final record = await TranslationService.translateArticle(article);
      if (record.translatedContent != null &&
          record.translatedContent!.isNotEmpty) {
        onTranslateSuccess?.call();
        AppFeedback.success('翻译完成', '已生成文章译文');
      } else {
        AppFeedback.error('翻译失败', record.errorMessage ?? '请检查网络连接和 API 配置');
      }
    } catch (e) {
      AppFeedback.error('翻译失败', e.toString());
    }
  }

  Future<void> _summarizeArticle() async {
    try {
      final record = await SummaryService.summarizeArticle(article);
      if (record.summaryText != null && record.summaryText!.isNotEmpty) {
        AppFeedback.success('摘要完成', '已生成文章摘要');
      } else {
        AppFeedback.error('摘要失败', record.errorMessage ?? '请检查网络连接和 API 配置');
      }
    } catch (e) {
      AppFeedback.error('摘要失败', e.toString());
    }
  }

  void _showAiActionsMenu(
    BuildContext context, {
    required bool isTranslated,
    required bool isTranslationPending,
    required bool hasSummary,
    required bool isSummaryPending,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: isTranslationPending
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.primary,
                        ),
                      )
                    : Icon(Icons.translate, color: colorScheme.primary),
                title: Text(
                  isTranslationPending
                      ? '翻译中...'
                      : (isTranslated ? '重新翻译' : '翻译文章'),
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                enabled: !isTranslationPending,
                onTap: isTranslationPending
                    ? null
                    : () {
                        Navigator.pop(context);
                        _translateArticle();
                      },
              ),
              if (isTranslated) ...[
                ListTile(
                  leading: Icon(Icons.delete_outline, color: colorScheme.error),
                  title: Text(
                    '删除翻译',
                    style: TextStyle(color: colorScheme.error),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    TranslationService.deleteTranslation(article.entryId);
                  },
                ),
              ],
              const Divider(height: 1),
              ListTile(
                leading: isSummaryPending
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.secondary,
                        ),
                      )
                    : Icon(Icons.summarize, color: colorScheme.secondary),
                title: Text(
                  isSummaryPending ? '摘要中...' : (hasSummary ? '重新摘要' : '生成摘要'),
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                enabled: !isSummaryPending,
                onTap: isSummaryPending
                    ? null
                    : () {
                        Navigator.pop(context);
                        _summarizeArticle();
                      },
              ),
              if (hasSummary) ...[
                ListTile(
                  leading: Icon(Icons.delete_outline, color: colorScheme.error),
                  title: Text(
                    '删除摘要',
                    style: TextStyle(color: colorScheme.error),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    SummaryService.deleteSummary(article.entryId);
                  },
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showMacOSContextMenu(
    BuildContext context,
    Offset position, {
    required bool isTranslated,
    required bool isTranslationPending,
    required bool hasSummary,
    required bool isSummaryPending,
  }) async {
    final colorScheme = Theme.of(context).colorScheme;

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'translate',
          enabled: !isTranslationPending,
          child: Row(
            children: [
              isTranslationPending
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.primary,
                      ),
                    )
                  : Icon(Icons.translate, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                isTranslationPending
                    ? '翻译中...'
                    : (isTranslated ? '重新翻译' : '翻译文章'),
              ),
            ],
          ),
        ),
        if (isTranslated)
          PopupMenuItem(
            value: 'delete_translation',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 18, color: colorScheme.error),
                const SizedBox(width: 8),
                Text('删除翻译', style: TextStyle(color: colorScheme.error)),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'summarize',
          enabled: !isSummaryPending,
          child: Row(
            children: [
              isSummaryPending
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.secondary,
                      ),
                    )
                  : Icon(
                      Icons.summarize,
                      size: 18,
                      color: colorScheme.secondary,
                    ),
              const SizedBox(width: 8),
              Text(
                isSummaryPending ? '摘要中...' : (hasSummary ? '重新摘要' : '生成摘要'),
              ),
            ],
          ),
        ),
        if (hasSummary)
          PopupMenuItem(
            value: 'delete_summary',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 18, color: colorScheme.error),
                const SizedBox(width: 8),
                Text('删除摘要', style: TextStyle(color: colorScheme.error)),
              ],
            ),
          ),
      ],
    );

    if (result == 'translate') {
      _translateArticle();
    } else if (result == 'delete_translation') {
      TranslationService.deleteTranslation(article.entryId);
    } else if (result == 'summarize') {
      _summarizeArticle();
    } else if (result == 'delete_summary') {
      SummaryService.deleteSummary(article.entryId);
    }
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
