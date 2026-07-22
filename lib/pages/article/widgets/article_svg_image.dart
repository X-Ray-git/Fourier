import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../services/article_image_cache_service.dart';

class ArticleSvgImage extends StatefulWidget {
  final String articleId;
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget placeholder;
  final Widget errorWidget;

  const ArticleSvgImage({
    super.key,
    required this.articleId,
    required this.imageUrl,
    required this.placeholder,
    required this.errorWidget,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
  });

  @override
  State<ArticleSvgImage> createState() => _ArticleSvgImageState();
}

class _ArticleSvgImageState extends State<ArticleSvgImage> {
  late Future<File> _file;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ArticleSvgImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.articleId != widget.articleId ||
        oldWidget.imageUrl != widget.imageUrl) {
      _load();
    }
  }

  void _load() {
    _file = ArticleImageCacheService.getImageFile(
      widget.articleId,
      widget.imageUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File>(
      future: _file,
      builder: (context, snapshot) {
        if (snapshot.hasError) return widget.errorWidget;
        final file = snapshot.data;
        if (file == null) return widget.placeholder;
        return SvgPicture.file(
          file,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          errorBuilder: (context, error, stackTrace) => widget.errorWidget,
        );
      },
    );
  }
}
