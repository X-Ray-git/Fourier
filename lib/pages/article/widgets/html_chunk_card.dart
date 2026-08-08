import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html_table/flutter_html_table.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../../common/widgets/feedback_toast.dart';
import '../../../common/widgets/app_context_menu.dart';
import '../../../common/widgets/app_glass.dart';
import '../../../utils/article_content_utils.dart';
import '../../../utils/bilibili_embed_utils.dart';
import '../../../utils/html_chunk_parser.dart';
import '../../../utils/youtube_embed_utils.dart';
import '../../../utils/html_contrast_utils.dart';
import '../../../utils/image_clipboard.dart';
import '../../../utils/macos_zoom_in_cursor.dart';
import '../../../services/article_image_service.dart';
import '../../../services/article_image_cache_service.dart';
import '../../../services/external_link_service.dart';
import 'bilibili_embed_player.dart';
import 'article_svg_image.dart';
import 'inline_video_player.dart';
import 'youtube_embed_player.dart';

double _fallbackImageHeight(double width) =>
    (width * 0.6).clamp(180.0, 420.0).toDouble();

double _maxStableImageHeight(double width) =>
    (width * 3.0).clamp(420.0, 1400.0).toDouble();

double _boundedImageHeight(double height, double width) =>
    height.clamp(0.0, _maxStableImageHeight(width)).toDouble();

double? _stylePixelHeight(String? style) {
  if (style == null || style.isEmpty) return null;
  final match = RegExp(
    r'(?:max-height|height)\s*:\s*(\d+(?:\.\d+)?)\s*px',
    caseSensitive: false,
  ).firstMatch(style);
  if (match == null) return null;
  return double.tryParse(match.group(1)!);
}

double? _stylePixelWidth(String? style) {
  if (style == null || style.isEmpty) return null;
  final match = RegExp(
    r'(?:max-width|width)\s*:\s*(\d+(?:\.\d+)?)\s*px',
    caseSensitive: false,
  ).firstMatch(style);
  if (match == null) return null;
  return double.tryParse(match.group(1)!);
}

double _imageWidthCap(double maxWidth) {
  if (maxWidth <= 0) return 0;
  return maxWidth;
}

double _resolvedImageWidth(
  double maxWidth, {
  double? imageWidth,
  String? style,
}) {
  final cap = _imageWidthCap(maxWidth);
  if (cap <= 0) return 0;

  final preferredWidth = (imageWidth != null && imageWidth > 0)
      ? imageWidth
      : _stylePixelWidth(style);
  if (preferredWidth != null && preferredWidth > 0) {
    return preferredWidth.clamp(1.0, cap).toDouble();
  }
  return cap;
}

double _stableImageHeight(
  double width, {
  double? imageWidth,
  double? imageHeight,
  String? style,
}) {
  if (imageWidth != null &&
      imageHeight != null &&
      imageWidth > 0 &&
      imageHeight > 0) {
    return _boundedImageHeight(width * imageHeight / imageWidth, width);
  }

  final styleHeight = _stylePixelHeight(style);
  if (styleHeight != null && styleHeight > 0) {
    return _boundedImageHeight(styleHeight, width);
  }

  return _fallbackImageHeight(width);
}

/// 单块渲染器 — 根据 HtmlChunkType 渲染对应 Widget，
/// 自动包裹 RepaintBoundary。
/// 修改为 StatefulWidget 并混入 AutomaticKeepAliveClientMixin，
/// 彻底解决由于列表回收引发 flutter_html 重复解析导致的滑动掉帧问题。
class HtmlChunkCard extends StatefulWidget {
  final HtmlChunk chunk;
  final String articleId;
  final String articleUrl;
  final double maxWidth;
  final void Function(String imageUrl)? onImageTap;
  final bool keepAlive;

  /// 由活动页面 State 提供的生命周期安全 hover 回调：
  /// [LinkHoverCallback] 只在 State mounted 时写入预览状态，
  /// 避免生成后的旧 TextSpan/MouseRegion 持有可能已销毁的 ValueNotifier。
  final LinkHoverCallback? onLinkHover;
  final Key? contentAnchorKey;
  final ValueChanged<double>? onEmbeddedPointerScroll;

  const HtmlChunkCard({
    super.key,
    required this.chunk,
    required this.articleId,
    this.articleUrl = '',
    required this.maxWidth,
    this.onImageTap,
    this.keepAlive = true,
    this.onLinkHover,
    this.contentAnchorKey,
    this.onEmbeddedPointerScroll,
  });

  @override
  State<HtmlChunkCard> createState() => _HtmlChunkCardState();
}

class _HtmlChunkCardState extends State<HtmlChunkCard>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.keepAlive; // 长文虚拟列表可关闭，降低内存峰值

  // 缓存：避免每次父级重建时重新解析 HTML。
  // flutter_html 的 Html() 调用是 CPU 密集操作（HTML 字符串 → Widget 树）。
  // 同一篇文章内 chunk 内容不变、主题不变 → 缓存 hit，build 耗时从 ms 级降到 ns 级。
  Widget? _cachedWidget;
  Brightness? _cachedBrightness;
  bool _codeCopied = false;

  HtmlExtension? _getLinkExtension(BuildContext context) {
    if (widget.onLinkHover == null) return null;
    return _InteractiveLinkExtension(
      onHoverChange: widget.onLinkHover,
      colorScheme: Theme.of(context).colorScheme,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _buildCardContent(context);
  }

  Widget _buildCardContent(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    if (_cachedWidget == null || _cachedBrightness != brightness) {
      _cachedWidget = _buildContent(context);
      _cachedBrightness = brightness;
    }

    if (_cachedWidget == null) return const SizedBox.shrink();

    final content = RepaintBoundary(
      child: widget.contentAnchorKey == null
          ? _cachedWidget!
          : KeyedSubtree(key: widget.contentAnchorKey!, child: _cachedWidget!),
    );

    return Padding(padding: _paddingForType, child: content);
  }

  // 优化垂直阅读节奏 (Vertical Rhythm)
  EdgeInsets get _paddingForType => switch (widget.chunk.type) {
    HtmlChunkType.heading => const EdgeInsets.only(top: 24, bottom: 8),
    HtmlChunkType.paragraph => const EdgeInsets.only(bottom: 14),
    HtmlChunkType.image => const EdgeInsets.symmetric(vertical: 12),
    HtmlChunkType.codeBlock => const EdgeInsets.only(bottom: 16),
    HtmlChunkType.blockquote => const EdgeInsets.only(bottom: 16),
    HtmlChunkType.table => const EdgeInsets.only(bottom: 16),
    HtmlChunkType.list => const EdgeInsets.only(bottom: 14),
    HtmlChunkType.horizontalRule => const EdgeInsets.symmetric(vertical: 16),
    HtmlChunkType.iframeVideo => const EdgeInsets.symmetric(vertical: 12),
    HtmlChunkType.rawHtml => const EdgeInsets.only(bottom: 14),
    HtmlChunkType.authorList => const EdgeInsets.only(bottom: 20),
  };

  Widget? _buildContent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return switch (widget.chunk.type) {
      HtmlChunkType.heading => _buildHeading(context, colorScheme),
      HtmlChunkType.paragraph => _buildParagraph(context, colorScheme),
      HtmlChunkType.image => _buildImage(context),
      HtmlChunkType.codeBlock => _buildCodeBlock(context, colorScheme),
      HtmlChunkType.blockquote => _buildBlockquote(context, colorScheme),
      HtmlChunkType.table => _buildTable(context, colorScheme),
      HtmlChunkType.list => _buildList(context, colorScheme),
      HtmlChunkType.horizontalRule => _buildDivider(colorScheme),
      HtmlChunkType.iframeVideo => _buildMediaPlaceholder(context, colorScheme),
      HtmlChunkType.rawHtml => _buildRawHtml(context, colorScheme),
      HtmlChunkType.authorList => _buildAuthorList(context, colorScheme),
    };
  }

  Widget _buildAuthorList(BuildContext context, ColorScheme cs) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    const avatarSize = 36.0;
    final cacheWidth = math.max(1, (avatarSize * dpr).round());
    final itemWidth = math.min(176.0, widget.maxWidth);

    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        children: widget.chunk.authors
            .map((author) {
              ArticleImageCacheService.registerImage(
                widget.articleId,
                author.avatarUrl,
                maxWidth: cacheWidth * 2,
              );

              final fallbackLetter = author.name.characters.firstOrNull ?? '';
              Widget item = SizedBox(
                width: itemWidth,
                child: Row(
                  children: [
                    ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: author.avatarUrl,
                        cacheKey: ArticleImageCacheService.displayCacheKey(
                          widget.articleId,
                          author.avatarUrl,
                        ),
                        httpHeaders: ArticleImageService.httpHeaders,
                        width: avatarSize,
                        height: avatarSize,
                        fit: BoxFit.cover,
                        memCacheWidth: cacheWidth,
                        maxWidthDiskCache: cacheWidth * 2,
                        fadeInDuration: const Duration(milliseconds: 80),
                        fadeOutDuration: const Duration(milliseconds: 80),
                        placeholder: (context, url) => Container(
                          width: avatarSize,
                          height: avatarSize,
                          color: cs.surfaceContainerHighest.withValues(
                            alpha: 0.3,
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          width: avatarSize,
                          height: avatarSize,
                          alignment: Alignment.center,
                          color: cs.surfaceContainerHighest.withValues(
                            alpha: 0.5,
                          ),
                          child: Text(
                            fallbackLetter,
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            author.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: cs.onSurface,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (author.handle.isNotEmpty) ...[
                            const SizedBox(height: 1),
                            Text(
                              '@${author.handle}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );

              if (author.profileUrl.isNotEmpty) {
                item = MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _openExternalUrl(author.profileUrl),
                    child: item,
                  ),
                );
              }

              return Semantics(
                label: author.name,
                button: author.profileUrl.isNotEmpty,
                child: item,
              );
            })
            .toList(growable: false),
      ),
    );
  }

  Future<void> _handleLinkTap(
    String? url,
    Map<String, String> attributes,
    dynamic element,
  ) async {
    if (url != null && url.isNotEmpty) {
      await ExternalLinkService.openUrlWithFeedback(url);
    }
  }

  // ── 标题 ──

  Widget _buildHeading(BuildContext context, ColorScheme cs) {
    final fontSize = switch (widget.chunk.headingLevel) {
      1 => 24.0,
      2 => 20.0,
      3 => 18.0,
      4 => 16.0,
      _ => 15.0,
    };
    String htmlData = widget.chunk.content;
    if (Theme.of(context).brightness == Brightness.dark) {
      htmlData = HtmlContrastUtils.adjustHtmlContrast(htmlData, cs.surface);
    }
    final ext = _getLinkExtension(context);
    return Html(
      data: htmlData,
      onLinkTap: _handleLinkTap,
      style: {
        'body': Style(
          fontSize: FontSize(fontSize),
          fontWeight: FontWeight.bold,
          color: cs.onSurface,
          lineHeight: const LineHeight(1.35),
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
        ),
        'a': Style(color: cs.primary, textDecoration: TextDecoration.none),
      },
      extensions: ext != null ? [ext] : const [],
    );
  }

  // ── 段落 ──

  Widget _buildParagraph(BuildContext context, ColorScheme cs) {
    // 已经移除了之前错误的 \n\n 合并，此处不需要给不是段落的元素强制套 <p>
    // 但为了确保样式生效，如果没有外层标签可以套一个 div
    String htmlData = '<div>${widget.chunk.content}</div>';
    if (Theme.of(context).brightness == Brightness.dark) {
      htmlData = HtmlContrastUtils.adjustHtmlContrast(htmlData, cs.surface);
    }
    return Html(
      data: htmlData,
      onLinkTap: _handleLinkTap,
      style: {
        'body': Style(
          fontSize: FontSize(16),
          lineHeight: const LineHeight(1.7),
          color: cs.onSurface,
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
          textAlign: TextAlign.start,
        ),
        'p': Style(margin: Margins.zero, padding: HtmlPaddings.zero),
        'a': Style(color: cs.primary),
        'strong': Style(fontWeight: FontWeight.w700),
        'em': Style(fontStyle: FontStyle.italic),
        'code': Style(
          fontFamily: 'monospace',
          fontFamilyFallback: const [
            'Menlo',
            'Monaco',
            'Courier New',
            'Courier',
          ],
          fontSize: FontSize(14),
        ),
      },
      extensions: _buildCommonExtensions(context, cs),
    );
  }

  List<HtmlExtension> _buildCommonExtensions(
    BuildContext context,
    ColorScheme cs,
  ) {
    final exts = <HtmlExtension>[
      _imageExtension(context),
      TableHtmlExtension(),
      InlineCodeExtension(colorScheme: cs),
    ];
    final linkExt = _getLinkExtension(context);
    if (linkExt != null) exts.add(linkExt);
    return exts;
  }

  // ── 图片 ──

  Widget _buildImage(BuildContext context) {
    final imageUrl = widget.chunk.normalizedImageUrl;
    if (imageUrl == null) return const SizedBox.shrink();
    return _ArticleInlineImage(
      articleId: widget.articleId,
      imageUrl: imageUrl,
      maxWidth: widget.maxWidth,
      imageWidth: widget.chunk.imageWidth,
      imageHeight: widget.chunk.imageHeight,
      style: widget.chunk.attributes['style'],
      className: widget.chunk.attributes['class'],
      onTap: widget.onImageTap,
    );
  }

  // ── 代码块 ──

  Widget _buildCodeBlock(BuildContext context, ColorScheme cs) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 42, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                widget.chunk.content,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: cs.onSurface,
                  height: 1.5,
                ),
              ),
            ),
          ),
          Positioned(
            top: 5,
            right: 5,
            child: AppGlassTooltip(
              message: _codeCopied ? '已复制' : '复制代码',
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: InkResponse(
                  radius: 18,
                  onTap: _copyCodeBlock,
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: Icon(
                      _codeCopied ? Icons.check_rounded : Icons.copy_rounded,
                      size: 16,
                      color: _codeCopied ? cs.primary : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyCodeBlock() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.chunk.content));
    } catch (error) {
      AppFeedback.error('复制失败', error.toString());
      return;
    }
    if (!mounted) return;
    setState(() {
      _codeCopied = true;
      _cachedWidget = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    setState(() {
      _codeCopied = false;
      _cachedWidget = null;
    });
  }

  // ── 引用 ──

  Widget _buildBlockquote(BuildContext context, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.25),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
        border: Border(left: BorderSide(color: cs.primary, width: 4)),
      ),
      child: Html(
        data: Theme.of(context).brightness == Brightness.dark
            ? HtmlContrastUtils.adjustHtmlContrast(
                widget.chunk.content,
                cs.surface,
              )
            : widget.chunk.content,
        onLinkTap: _handleLinkTap,
        style: {
          'body': Style(
            fontSize: FontSize(15),
            lineHeight: const LineHeight(1.6),
            color: cs.onSurfaceVariant,
            fontStyle: FontStyle.italic,
            margin: Margins.zero,
            padding: HtmlPaddings.zero,
          ),
          'a': Style(color: cs.primary),
        },
        extensions: _buildCommonExtensions(context, cs),
      ),
    );
  }

  // ── 表格 ──

  Widget _buildTable(BuildContext context, ColorScheme cs) {
    final tableRows = _parseTableRows(widget.chunk.content);
    if (tableRows.isEmpty) return const SizedBox.shrink();

    final columnCount = tableRows.fold<int>(
      0,
      (maxCount, row) => math.max(maxCount, row.length),
    );
    if (columnCount == 0) return const SizedBox.shrink();

    final columnWidth = math.max(
      112.0,
      math.min(180.0, widget.maxWidth / math.min(columnCount, 4)),
    );
    final tableWidth = columnWidth * columnCount;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: widget.maxWidth,
          maxWidth: math.max(widget.maxWidth, tableWidth),
        ),
        child: Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: TableBorder.all(color: cs.outlineVariant, width: 0.8),
          columnWidths: {
            for (var i = 0; i < columnCount; i++)
              i: FixedColumnWidth(columnWidth),
          },
          children: [
            for (var rowIndex = 0; rowIndex < tableRows.length; rowIndex++)
              TableRow(
                decoration: BoxDecoration(
                  color: rowIndex == 0
                      ? cs.surfaceContainerHighest.withValues(alpha: 0.55)
                      : Colors.transparent,
                ),
                children: [
                  for (var cellIndex = 0; cellIndex < columnCount; cellIndex++)
                    _buildTableCell(
                      context,
                      cs,
                      cellIndex < tableRows[rowIndex].length
                          ? tableRows[rowIndex][cellIndex]
                          : const _ArticleTableCell(''),
                      isHeader: rowIndex == 0,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  List<List<_ArticleTableCell>> _parseTableRows(String html) {
    final fragment = html_parser.parseFragment(html);
    final table = fragment.querySelector('table');
    if (table == null) return const [];

    final rows = <List<_ArticleTableCell>>[];
    for (final tr in table.querySelectorAll('tr')) {
      final cells = <_ArticleTableCell>[];
      for (final child in tr.children) {
        final tag = child.localName?.toLowerCase();
        if (tag != 'td' && tag != 'th') continue;

        final text = child.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        final colSpan = int.tryParse(child.attributes['colspan'] ?? '') ?? 1;
        final normalizedSpan = colSpan.clamp(1, 12);
        cells.add(_ArticleTableCell(text, isHeader: tag == 'th'));
        for (var i = 1; i < normalizedSpan; i++) {
          cells.add(const _ArticleTableCell(''));
        }
      }
      if (cells.any((cell) => cell.text.isNotEmpty)) {
        rows.add(cells);
      }
    }
    return rows;
  }

  Widget _buildTableCell(
    BuildContext context,
    ColorScheme cs,
    _ArticleTableCell cell, {
    required bool isHeader,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Text(
        cell.text,
        style: TextStyle(
          fontSize: 14,
          height: 1.45,
          color: cs.onSurface,
          fontWeight: (isHeader || cell.isHeader)
              ? FontWeight.w700
              : FontWeight.w400,
        ),
      ),
    );
  }

  // ── 列表 ──

  Widget _buildList(BuildContext context, ColorScheme cs) {
    String htmlData = widget.chunk.content;
    if (Theme.of(context).brightness == Brightness.dark) {
      htmlData = HtmlContrastUtils.adjustHtmlContrast(htmlData, cs.surface);
    }
    return Html(
      data: htmlData,
      onLinkTap: _handleLinkTap,
      style: {
        'body': Style(
          fontSize: FontSize(16),
          lineHeight: const LineHeight(1.5),
          color: cs.onSurface,
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
        ),
        'a': Style(color: cs.primary, textDecoration: TextDecoration.none),
        'strong': Style(fontWeight: FontWeight.w700),
        'em': Style(fontStyle: FontStyle.italic),
        'code': Style(
          fontFamily: 'monospace',
          fontFamilyFallback: const [
            'Menlo',
            'Monaco',
            'Courier New',
            'Courier',
          ],
          fontSize: FontSize(14),
        ),
        'ul': Style(padding: HtmlPaddings.only(left: 20), margin: Margins.zero),
        'ol': Style(padding: HtmlPaddings.only(left: 20), margin: Margins.zero),
      },
      extensions: _buildCommonExtensions(context, cs),
    );
  }

  // ── 分割线 ──

  Widget _buildDivider(ColorScheme cs) {
    return Divider(color: cs.outlineVariant, height: 1);
  }

  // ── 媒体占位 ──

  Widget _buildMediaPlaceholder(BuildContext context, ColorScheme cs) {
    final isVideo = widget.chunk.attributes['mediaTag'] == 'video';
    final videoUrl = widget.chunk.imageSrc;
    if (widget.chunk.attributes['mediaUnavailableReason'] == 'missingSource' ||
        videoUrl == null ||
        videoUrl.isEmpty) {
      return _buildUnavailableMedia(context, cs);
    }
    final posterUrl = widget.chunk.posterSrc != null
        ? ArticleImageService.toProxiedUrl(widget.chunk.posterSrc)
        : null;
    final aspectRatio =
        (widget.chunk.imageWidth != null &&
            widget.chunk.imageHeight != null &&
            widget.chunk.imageHeight! > 0)
        ? widget.chunk.imageWidth! / widget.chunk.imageHeight!
        : 16 / 9;

    // 视频 → 内联播放器
    if (isVideo) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: InlineVideoPlayer(
          videoUrl: videoUrl,
          posterUrl: posterUrl,
          articleUrl: widget.articleUrl,
        ),
      );
    }

    final youtube = YouTubeEmbedInfo.tryParse(videoUrl);
    if (youtube != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: YouTubeEmbedPlayer(
          info: youtube,
          onArticleScroll: widget.onEmbeddedPointerScroll,
        ),
      );
    }

    final bilibili = BilibiliEmbedInfo.tryParse(videoUrl);
    if (bilibili != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: BilibiliEmbedPlayer(
          info: bilibili,
          onArticleScroll: widget.onEmbeddedPointerScroll,
        ),
      );
    }

    // iframe / 其他 → 静态占位 + 浏览器打开
    return _buildIframePlaceholder(context, cs, aspectRatio);
  }

  Widget _buildUnavailableMedia(BuildContext context, ColorScheme cs) {
    final mediaTag = widget.chunk.attributes['mediaTag'];
    final (icon, title) = switch (mediaTag) {
      'audio' => (Icons.audio_file_outlined, '音频不可用'),
      'video' => (Icons.videocam_off_outlined, '视频不可用'),
      _ => (Icons.web_asset_off_outlined, '嵌入内容不可用'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.7),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '源内容未提供可用的媒体地址',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
          if (widget.articleUrl.isNotEmpty) ...[
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: () => _openExternalUrl(widget.articleUrl),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('打开原文'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openExternalUrl(String url) async {
    await ExternalLinkService.openUrlWithFeedback(url);
  }

  Widget _buildIframePlaceholder(
    BuildContext context,
    ColorScheme cs,
    double aspectRatio,
  ) {
    final url = widget.chunk.imageSrc;
    final posterUrl = widget.chunk.posterSrc != null
        ? ArticleImageService.toProxiedUrl(widget.chunk.posterSrc)
        : null;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.maxWidth, maxHeight: 400),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 背景：poster 图片 或 纯色
              if (posterUrl != null)
                CachedNetworkImage(
                  imageUrl: posterUrl,
                  httpHeaders: ArticleImageService.httpHeaders,
                  fit: BoxFit.cover,
                  fadeInDuration: const Duration(milliseconds: 250),
                  fadeOutDuration: const Duration(milliseconds: 80),
                  placeholder: (context, url) =>
                      Container(color: cs.surfaceContainerHighest),
                  errorWidget: (context, url, error) =>
                      Container(color: cs.surfaceContainerHighest),
                )
              else
                Container(color: cs.surfaceContainerHighest),

              // 渐变暗角遮罩，提升整体质感，代替生硬的纯黑透明度
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.6),
                    ],
                    stops: const [0.6, 1.0],
                  ),
                ),
              ),

              // 居中毛玻璃按钮
              Center(
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: InkWell(
                      onTap: () async {
                        if (url != null && url.isNotEmpty) {
                          await ExternalLinkService.openUrlWithFeedback(url);
                        }
                      },
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: cs.onPrimaryContainer.withValues(alpha: 0.2),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          Icons.language,
                          size: 32,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // 底部标签：毛玻璃药丸风格
              Positioned(
                bottom: 12,
                right: 12,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                          width: 0.5,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.open_in_new,
                            size: 12,
                            color: Colors.white,
                          ),
                          SizedBox(width: 4),
                          Text(
                            '外部网页',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 兜底 HTML ──

  Widget _buildRawHtml(BuildContext context, ColorScheme cs) {
    return Html(
      data: Theme.of(context).brightness == Brightness.dark
          ? HtmlContrastUtils.adjustHtmlContrast(
              widget.chunk.content,
              cs.surface,
            )
          : widget.chunk.content,
      onLinkTap: _handleLinkTap,
      style: {
        'body': Style(
          fontSize: FontSize(16),
          lineHeight: const LineHeight(1.7),
          color: cs.onSurface,
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
        ),
        'a': Style(color: cs.primary),
      },
      extensions: _buildCommonExtensions(context, cs),
    );
  }

  /// 共享的图片渲染扩展：使用 CachedNetworkImage + 统一请求头 + 点击放大
  ImageExtension _imageExtension(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;

    return ImageExtension(
      builder: (extensionContext) {
        final imageUrl = ArticleContentUtils.imageUrlFromAttributes(
          extensionContext.attributes,
        );
        if (imageUrl == null) {
          return const SizedBox.shrink();
        }

        final attrs = extensionContext.attributes;
        double? explicitWidth;
        double? explicitHeight;

        if (attrs['width'] != null) {
          explicitWidth = double.tryParse(
            attrs['width']!.replaceAll(RegExp(r'[^0-9.]'), ''),
          );
        }
        if (attrs['height'] != null) {
          explicitHeight = double.tryParse(
            attrs['height']!.replaceAll(RegExp(r'[^0-9.]'), ''),
          );
        }

        final isInlineEmoji =
            imageUrl.contains('s.w.org/images/core/emoji') ||
            attrs['class'] == 'emoji';

        // 针对常见的 WordPress emoji 等内联小图做默认尺寸约束
        if (isInlineEmoji) {
          explicitWidth ??= 20.0;
          explicitHeight ??= 20.0;
        }

        final renderWidth = _resolvedImageWidth(
          widget.maxWidth,
          imageWidth: explicitWidth,
          style: attrs['style'],
        );
        final renderHeight = _stableImageHeight(
          renderWidth,
          imageWidth: explicitWidth,
          imageHeight: explicitHeight,
          style: attrs['style'],
        );
        final cacheWidth = math.max(1, (renderWidth * dpr).round());
        final diskCacheWidth = cacheWidth * 2;
        ArticleImageCacheService.registerImage(
          widget.articleId,
          imageUrl,
          maxWidth: diskCacheWidth,
        );

        final imageWidget = ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ArticleImageService.isSvg(imageUrl)
              ? GestureDetector(
                  onTap: widget.onImageTap != null
                      ? () => widget.onImageTap!(imageUrl)
                      : null,
                  onSecondaryTapDown: Platform.isMacOS
                      ? (details) => showInlineImageContextMenu(
                          context,
                          details.globalPosition,
                          imageUrl,
                        )
                      : null,
                  child: ArticleSvgImage(
                    articleId: widget.articleId,
                    imageUrl: imageUrl,
                    width: renderWidth,
                    fit: BoxFit.contain,
                    placeholder: SizedBox(
                      width: renderWidth,
                      height: renderHeight,
                      child: const Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                    errorWidget: Container(
                      width: renderWidth,
                      height: renderHeight,
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.2),
                      child: const Center(
                        child: Icon(Icons.broken_image_outlined, size: 20),
                      ),
                    ),
                  ),
                )
              : CachedNetworkImage(
                  imageUrl: imageUrl,
                  cacheKey: ArticleImageCacheService.displayCacheKey(
                    widget.articleId,
                    imageUrl,
                  ),
                  httpHeaders: ArticleImageService.httpHeaders,
                  fit: BoxFit.contain,
                  width: renderWidth,
                  memCacheWidth: cacheWidth,
                  maxWidthDiskCache: diskCacheWidth,
                  fadeInDuration: const Duration(milliseconds: 80),
                  fadeOutDuration: const Duration(milliseconds: 80),
                  placeholder: (context, url) => SizedBox(
                    width: renderWidth,
                    height: renderHeight,
                    child: const Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    width: renderWidth,
                    height: renderHeight,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.2),
                    child: const Center(
                      child: Icon(Icons.broken_image_outlined, size: 20),
                    ),
                  ),
                  imageBuilder: (ctx, imageProvider) {
                    final gesture = GestureDetector(
                      onTap: widget.onImageTap != null
                          ? () => widget.onImageTap!(imageUrl)
                          : null,
                      onSecondaryTapDown: Platform.isMacOS
                          ? (details) => showInlineImageContextMenu(
                              ctx,
                              details.globalPosition,
                              imageUrl,
                            )
                          : null,
                      child: SizedBox(
                        width: renderWidth,
                        child: Image(image: imageProvider, fit: BoxFit.contain),
                      ),
                    );
                    return gesture;
                  },
                ),
        );

        if (isInlineEmoji) return imageWidget;
        return Center(child: imageWidget);
      },
    );
  }
}

// 2. 修复：混入 AutomaticKeepAliveClientMixin 以保持状态存活
class _ArticleInlineImage extends StatefulWidget {
  final String articleId;
  final String imageUrl;
  final double maxWidth;
  final double? imageWidth;
  final double? imageHeight;
  final String? style;
  final String? className;
  final void Function(String imageUrl)? onTap;

  const _ArticleInlineImage({
    required this.articleId,
    required this.imageUrl,
    required this.maxWidth,
    this.imageWidth,
    this.imageHeight,
    this.style,
    this.className,
    this.onTap,
  });

  @override
  State<_ArticleInlineImage> createState() => _ArticleInlineImageState();
}

class _ArticleInlineImageState extends State<_ArticleInlineImage>
    with AutomaticKeepAliveClientMixin {
  late ValueListenable<ArticleImageRetryState> _retryState;
  bool _reportedFailure = false;
  int _lastSuccessRevision = 0;

  @override
  void initState() {
    super.initState();
    _retryState = ArticleImageCacheService.acquireRetryState(
      widget.articleId,
      widget.imageUrl,
    );
  }

  @override
  bool get wantKeepAlive => true; // 告诉 ListView 不要在滑出屏幕时销毁该组件

  @override
  void didUpdateWidget(covariant _ArticleInlineImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.articleId != widget.articleId ||
        oldWidget.imageUrl != widget.imageUrl) {
      ArticleImageCacheService.releaseRetryState(
        oldWidget.articleId,
        oldWidget.imageUrl,
      );
      _retryState = ArticleImageCacheService.acquireRetryState(
        widget.articleId,
        widget.imageUrl,
      );
      _reportedFailure = false;
      _lastSuccessRevision = 0;
    }
  }

  @override
  void dispose() {
    ArticleImageCacheService.releaseRetryState(
      widget.articleId,
      widget.imageUrl,
    );
    super.dispose();
  }

  void _reportFailure() {
    if (_reportedFailure) return;
    _reportedFailure = true;
    final articleId = widget.articleId;
    final imageUrl = widget.imageUrl;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          widget.articleId != articleId ||
          widget.imageUrl != imageUrl) {
        return;
      }
      ArticleImageCacheService.scheduleRetryFromUi(articleId, imageUrl);
    });
  }

  void _retryManually() {
    ArticleImageCacheService.retryManually(widget.articleId, widget.imageUrl);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须在首行调用 super.build(context)

    final cs = Theme.of(context).colorScheme;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final displayWidth = _resolvedImageWidth(
      widget.maxWidth,
      imageWidth: widget.imageWidth,
      style: widget.style,
    );
    final cacheWidth = math.max(1, (displayWidth * dpr).round());
    final displayHeight = _stableImageHeight(
      displayWidth,
      imageWidth: widget.imageWidth,
      imageHeight: widget.imageHeight,
      style: widget.style,
    );

    final canTap = widget.onTap != null;
    final diskCacheWidth = cacheWidth * 2;
    ArticleImageCacheService.registerImage(
      widget.articleId,
      widget.imageUrl,
      maxWidth: diskCacheWidth,
    );

    Widget image = ValueListenableBuilder<ArticleImageRetryState>(
      valueListenable: _retryState,
      builder: (context, retryState, child) {
        if (retryState.successRevision != _lastSuccessRevision) {
          _lastSuccessRevision = retryState.successRevision;
          _reportedFailure = false;
        }
        final retryKey = ValueKey(
          '${widget.articleId}:${widget.imageUrl}:'
          '${retryState.successRevision}',
        );
        final errorWidget = SizedBox(
          width: displayWidth,
          height: displayHeight,
          child: _ImageErrorWidget(
            cs: cs,
            retrying: retryState.retrying,
            onRetry: _retryManually,
          ),
        );

        return Hero(
          tag: widget.imageUrl,
          child: ArticleImageService.isSvg(widget.imageUrl)
              ? ArticleSvgImage(
                  key: retryKey,
                  articleId: widget.articleId,
                  imageUrl: widget.imageUrl,
                  width: displayWidth,
                  fit: BoxFit.contain,
                  onError: _reportFailure,
                  placeholder: SizedBox(
                    width: displayWidth,
                    height: displayHeight,
                    child: const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  errorWidget: errorWidget,
                )
              : CachedNetworkImage(
                  key: retryKey,
                  imageUrl: widget.imageUrl,
                  cacheKey: ArticleImageCacheService.displayCacheKey(
                    widget.articleId,
                    widget.imageUrl,
                  ),
                  httpHeaders: ArticleImageService.httpHeaders,
                  fit: BoxFit.contain,
                  width: displayWidth,
                  memCacheWidth: cacheWidth,
                  maxWidthDiskCache: diskCacheWidth,
                  fadeInDuration: const Duration(milliseconds: 250),
                  fadeOutDuration: const Duration(milliseconds: 80),
                  // 与全屏查看器共用统一成功通知路径。
                  imageBuilder: (context, imageProvider) {
                    ArticleImageCacheService.notifyImageLoadedSuccessfully(
                      widget.articleId,
                      widget.imageUrl,
                    );
                    return Image(
                      image: imageProvider,
                      fit: BoxFit.contain,
                      width: displayWidth,
                    );
                  },
                  placeholder: (context, url) => SizedBox(
                    width: displayWidth,
                    height: displayHeight,
                    child: const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) {
                    _reportFailure();
                    return errorWidget;
                  },
                ),
        );
      },
    );

    if (canTap) {
      image = GestureDetector(
        onTap: () => widget.onTap!(widget.imageUrl),
        child: image,
      );
    }
    if (Platform.isMacOS) {
      image = GestureDetector(
        onSecondaryTapDown: (details) => showInlineImageContextMenu(
          context,
          details.globalPosition,
          widget.imageUrl,
        ),
        child: image,
      );
    }

    image = ClipRRect(borderRadius: BorderRadius.circular(10), child: image);

    if (Platform.isMacOS) {
      image = MouseRegion(
        cursor: canTap ? MacOSZoomInCursor.instance : MouseCursor.defer,
        child: image,
      );
    } else {
      image = Material(type: MaterialType.transparency, child: image);
    }

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: displayWidth),
        child: image,
      ),
    );
  }
}

void showInlineImageContextMenu(
  BuildContext context,
  Offset position,
  String imageUrl,
) {
  () async {
    final value = await AppContextMenu.show<String>(
      context,
      position: position,
      minWidth: 132,
      entries: const [
        AppContextMenuAction(
          value: 'copy',
          icon: Icons.copy_rounded,
          label: '复制图片',
        ),
        AppContextMenuAction(
          value: 'copyLink',
          icon: Icons.link_rounded,
          label: '复制链接',
        ),
      ],
    );

    switch (value) {
      case 'copy':
        final bytes = await ImageClipboard.downloadBytes(imageUrl);
        if (bytes == null) {
          if (context.mounted) {
            AppFeedback.error('复制失败', '无法下载图片数据');
          }
          return;
        }
        final ok = await ImageClipboard.copyImageToClipboard(bytes);
        if (ok) {
          if (context.mounted) {
            AppFeedback.success('已复制', '图片已复制到剪贴板');
          }
        } else {
          if (context.mounted) {
            AppFeedback.error('复制失败', '请稍后重试');
          }
        }
      case 'copyLink':
        Clipboard.setData(ClipboardData(text: imageUrl));
        if (context.mounted) {
          AppFeedback.success('已复制', '图片链接已复制到剪贴板');
        }
      case null:
        break;
    }
  }();
}

class _ImageErrorWidget extends StatelessWidget {
  final ColorScheme cs;
  final VoidCallback onRetry;
  final bool retrying;

  /// [retrying] 为 true 时表示后台自动重试进行中，占位显示「重新加载中…」
  /// 且不可点击；为 false 时表示自动重试已耗尽，显示「图片加载失败，点击重试」
  /// 并允许用户手动触发兜底重试。
  const _ImageErrorWidget({
    required this.cs,
    required this.onRetry,
    this.retrying = false,
  });

  @override
  Widget build(BuildContext context) {
    if (retrying) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, color: cs.onSurfaceVariant, size: 36),
          const SizedBox(height: 6),
          Text(
            '重新加载中…',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      );
    }
    return InkWell(
      onTap: onRetry,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.broken_image_outlined,
            color: cs.onSurfaceVariant,
            size: 36,
          ),
          const SizedBox(height: 6),
          Text(
            '图片加载失败，点击重试',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// 行内代码自定义扩展 — 使用 alphabetic baseline 对齐，
/// 替代 TagWrapExtension 的 bottom 对齐 + Transform.translate 补偿方案。
class InlineCodeExtension extends HtmlExtension {
  final ColorScheme colorScheme;
  const InlineCodeExtension({required this.colorScheme});

  @override
  Set<String> get supportedTags => {'code'};

  @override
  bool matches(ExtensionContext context) {
    switch (context.currentStep) {
      case CurrentStep.preparing:
        return super.matches(context);
      case CurrentStep.preStyling:
      case CurrentStep.preProcessing:
        return false;
      case CurrentStep.building:
        return context.styledElement is _InlineCodeWrapperElement;
    }
  }

  @override
  StyledElement prepare(
    ExtensionContext context,
    List<StyledElement> children,
  ) {
    return _InlineCodeWrapperElement(
      child: context.parser.prepareFromExtension(
        context,
        children,
        extensionsToIgnore: {this},
      ),
    );
  }

  @override
  InlineSpan build(ExtensionContext context) {
    final child = CssBoxWidget.withInlineSpanChildren(
      children: context.inlineSpanChildren!,
      style: context.style!,
    );

    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Container(
        // 仅 macOS 收窄行内代码的垂直内边距（2→1），Android 保持不变；
        // 字号、baseline、横向 padding 与块级代码不受影响。
        padding: EdgeInsets.symmetric(
          horizontal: 4,
          vertical: Platform.isMacOS ? 1 : 2,
        ),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(6),
        ),
        child: child,
      ),
    );
  }
}

class _InlineCodeWrapperElement extends StyledElement {
  _InlineCodeWrapperElement({required StyledElement child})
    : super(
        node: dom.Element.tag("inline-code-wrapper"),
        style: Style(),
        children: [child],
        name: "[inline-code-wrapper]",
      );
}

class _ArticleTableCell {
  final String text;
  final bool isHeader;

  const _ArticleTableCell(this.text, {this.isHeader = false});
}

/// hover 回调：[url] 为被悬停链接的 href；[isExit] 为 true 表示
/// 该链接的 hover 结束（进入/离开成对触发）。
typedef LinkHoverCallback = void Function(String? url, bool isExit);

/// 自定义 flutter_html 扩展：替换 `<a>` 标签的默认渲染，
/// 添加鼠标悬停手势 (SystemMouseCursors.click) 和链接 URL 预览回调。
///
/// 不直接持有任何 ValueNotifier：预览状态由活动页面 State 提供的
/// 生命周期安全回调维护，切换文章 / 播放器回退 / 快速移动鼠标时
/// 不会产生对已销毁 ValueNotifier 的写入。
class _InteractiveLinkExtension extends HtmlExtension {
  final LinkHoverCallback? onHoverChange;
  final ColorScheme colorScheme;

  _InteractiveLinkExtension({this.onHoverChange, required this.colorScheme});

  @override
  Set<String> get supportedTags => {'a'};

  @override
  bool matches(ExtensionContext context) {
    return context.elementName == 'a' && context.attributes.containsKey('href');
  }

  @override
  StyledElement prepare(
    ExtensionContext context,
    List<StyledElement> children,
  ) {
    final url = context.attributes['href'];

    return InteractiveElement(
      name: context.elementName,
      children: children,
      href: url,
      style: Style(
        color: colorScheme.primary,
        textDecoration: TextDecoration.none,
        textDecorationColor: colorScheme.primary,
      ),
      node: context.node,
      elementId: context.id,
    );
  }

  @override
  InlineSpan build(ExtensionContext context) {
    final url = context.attributes['href'];
    return TextSpan(
      children: context.inlineSpanChildren!.map((childSpan) {
        return _processChild(context, childSpan, url);
      }).toList(),
    );
  }

  InlineSpan _processChild(
    ExtensionContext context,
    InlineSpan childSpan,
    String? url,
  ) {
    void onTap() => context.parser.internalOnAnchorTap?.call(
      url,
      context.attributes,
      context.node is dom.Element ? context.node as dom.Element : null,
    );

    void handleEnter(PointerEnterEvent _) => onHoverChange?.call(url, false);
    void handleExit(PointerExitEvent _) => onHoverChange?.call(url, true);

    if (childSpan is TextSpan) {
      return TextSpan(
        text: childSpan.text,
        children: childSpan.children
            ?.map((e) => _processChild(context, e, url))
            .toList(),
        recognizer: TapGestureRecognizer()..onTap = onTap,
        style:
            context.styledElement?.style.generateTextStyle() ?? childSpan.style,
        semanticsLabel: childSpan.semanticsLabel,
        locale: childSpan.locale,
        mouseCursor: SystemMouseCursors.click,
        onEnter: handleEnter,
        onExit: handleExit,
        spellOut: childSpan.spellOut,
      );
    } else {
      final alignment =
          context.style?.verticalAlign.toPlaceholderAlignment(
            context.style?.display,
          ) ??
          PlaceholderAlignment.baseline;
      return WidgetSpan(
        alignment: alignment,
        baseline: TextBaseline.alphabetic,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: handleEnter,
          onExit: handleExit,
          child: GestureDetector(
            onTap: onTap,
            child: (childSpan as WidgetSpan).child,
          ),
        ),
      );
    }
  }
}
