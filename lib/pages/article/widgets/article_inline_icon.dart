import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

import '../../../services/article_image_cache_service.dart';
import '../../../services/article_image_service.dart';
import '../../../utils/article_inline_icon.dart';
import 'macos_managed_animated_image.dart';

/// Generic presentation for small inline icons produced by source rules.
/// Platform-specific names and image mappings do not belong in the renderer.
class ArticleInlineIconExtension extends HtmlExtension {
  const ArticleInlineIconExtension({required this.articleId});

  final String articleId;

  @override
  Set<String> get supportedTags => {articleInlineIconTag};

  @override
  InlineSpan build(ExtensionContext context) {
    final label = context.element?.text ?? '';
    final url =
        ArticleImageService.toProxiedUrl(context.attributes['src'] ?? '') ?? '';
    final uri = Uri.tryParse(url);
    final style = context.style?.generateTextStyle();
    if (url.isEmpty || uri == null || !{'http', 'https'}.contains(uri.scheme)) {
      return TextSpan(text: label, style: style);
    }
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      rawText: label,
      child: ArticleInlineIcon(
        articleId: articleId,
        imageUrl: url,
        label: label,
        textStyle: style ?? const TextStyle(fontSize: 16),
      ),
    );
  }
}

class ArticleInlineIcon extends StatelessWidget {
  const ArticleInlineIcon({
    super.key,
    required this.articleId,
    required this.imageUrl,
    required this.label,
    required this.textStyle,
  });

  final String articleId;
  final String imageUrl;
  final String label;
  final TextStyle textStyle;

  @visibleForTesting
  static ImageProvider Function(String url)? debugImageProvider;

  @override
  Widget build(BuildContext context) {
    // RichText scales WidgetSpan children. Keep logical size unscaled here
    // to avoid applying the user's text scale twice.
    final fontSize = textStyle.fontSize ?? 16;
    final size = fontSize * 1.2;
    final scaledSize = MediaQuery.textScalerOf(context).scale(fontSize) * 1.2;
    final cacheWidth = (scaledSize * MediaQuery.devicePixelRatioOf(context))
        .ceil();
    ArticleImageCacheService.registerImage(
      articleId,
      imageUrl,
      maxWidth: cacheWidth,
    );
    final provider =
        debugImageProvider?.call(imageUrl) ??
        CachedNetworkImageProvider(
          imageUrl,
          cacheKey: ArticleImageCacheService.displayCacheKey(
            articleId,
            imageUrl,
          ),
          headers: ArticleImageService.httpHeaders,
          maxWidth: cacheWidth,
        );
    final fallback = Text(
      label,
      style: textStyle,
      textScaler: TextScaler.noScaling,
    );
    final Widget image;
    if (Platform.isMacOS &&
        ArticleImageCacheService.isLikelyAnimatedImage(imageUrl)) {
      image = MacosManagedAnimatedImage(
        imageProvider: provider,
        width: size,
        placeholder: fallback,
        errorWidget: fallback,
      );
    } else {
      image = Image(
        image: provider,
        width: size,
        height: size,
        fit: BoxFit.contain,
        frameBuilder: (_, child, frame, synchronous) =>
            frame != null || synchronous ? child : fallback,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    return Semantics(
      label: label,
      image: true,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: image,
      ),
    );
  }
}
