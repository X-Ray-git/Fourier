import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/article.dart';
import '../utils/article_content_utils.dart';
import 'article_image_cache_service.dart';
import 'article_image_service.dart';

class ArticleVisualContext {
  const ArticleVisualContext({
    required this.imageUrls,
    required this.totalImageCount,
  });

  final List<String> imageUrls;
  final int totalImageCount;

  bool get hasImages => imageUrls.isNotEmpty;

  String get structureMetadata =>
      '''
[结构信息]
正文图片总数：$totalImageCount
本轮可用正文图片数：${imageUrls.length}''';
}

/// 摘要和质量过滤共用的正文图片选择规则。
abstract final class ArticleVisualContextService {
  static const int maxImagesPerRequest = 8;
  static const int maxImageBytes = 8 * 1024 * 1024;
  // Base64 expands this to 32 MiB, leaving room below the API's 48 MiB limit.
  static const int maxTotalImageBytes = 24 * 1024 * 1024;

  @visibleForTesting
  static Future<File> Function(String articleId, String imageUrl)?
  debugImageFileLoader;

  static Future<List<String>> loadInlineImages(
    String articleId,
    List<String> imageUrls,
  ) async {
    if (imageUrls.length > maxImagesPerRequest) {
      throw StateError('Too many visual context images');
    }
    final result = <String>[];
    var totalBytes = 0;
    for (final url in imageUrls) {
      final file =
          await (debugImageFileLoader ?? ArticleImageCacheService.getImageFile)(
            articleId,
            url,
          );
      final handle = await file.open();
      late Uint8List bytes;
      try {
        final length = await handle.length();
        if (length <= 0 || length > maxImageBytes) {
          throw StateError(
            'Visual context image exceeds size limit or is empty',
          );
        }
        if (totalBytes + length > maxTotalImageBytes) {
          throw StateError('Visual context images exceed total size limit');
        }
        bytes = await handle.read(length);
        if (bytes.length != length) {
          throw StateError('Visual context image changed while reading');
        }
      } finally {
        await handle.close();
      }
      totalBytes += bytes.length;
      result.add(await compute(_encodeInlineImage, bytes));
    }
    return result;
  }

  static ArticleVisualContext prepare(
    ArticleModel article,
    String normalizedHtml,
  ) {
    final allUrls = ArticleContentUtils.extractImageUrls(
      normalizedHtml,
      sourceUrl: article.url,
    ).where((url) => !ArticleImageService.isSvg(url)).toList(growable: false);

    return ArticleVisualContext(
      imageUrls: List.unmodifiable(allUrls.take(maxImagesPerRequest)),
      totalImageCount: allUrls.length,
    );
  }
}

String _encodeInlineImage(Uint8List bytes) {
  bool startsWith(List<int> signature) {
    if (bytes.length < signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) return false;
    }
    return true;
  }

  final String mime;
  if (startsWith([0xff, 0xd8, 0xff])) {
    mime = 'image/jpeg';
  } else if (startsWith([137, 80, 78, 71, 13, 10, 26, 10])) {
    mime = 'image/png';
  } else if (startsWith(ascii.encode('GIF87a')) ||
      startsWith(ascii.encode('GIF89a'))) {
    mime = 'image/gif';
  } else if (bytes.length >= 12 &&
      startsWith(ascii.encode('RIFF')) &&
      ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
    mime = 'image/webp';
  } else {
    throw StateError('Unsupported visual context image format');
  }
  return 'data:$mime;base64,${base64Encode(bytes)}';
}
