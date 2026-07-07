import '../models/article.dart';
import 'article_content_utils.dart';
import 'html_chunk_parser.dart';

abstract final class ArticleLengthEstimator {
  static final Map<String, _CachedLength> _cache = {};

  static double estimateReadingHeight(ArticleModel article) {
    final rawContent = article.content ?? '';
    final signature =
        '${article.entryId}:${article.title.length}:${rawContent.length}:${rawContent.hashCode}';
    final cached = _cache[article.entryId];
    if (cached != null && cached.signature == signature) {
      return cached.height;
    }

    final titleHeight = _estimateTitleHeight(article.title);
    if (rawContent.trim().isEmpty) {
      final height = titleHeight + 120;
      _cache[article.entryId] = _CachedLength(signature, height);
      return height;
    }

    final normalized = ArticleContentUtils.normalizeHtml(rawContent);
    final chunks = HtmlChunkParser.parseSync(normalized);
    final bodyHeight = chunks.fold<double>(
      0,
      (total, chunk) => total + chunk.estimatedHeight,
    );
    final height = titleHeight + 180 + bodyHeight;
    _cache[article.entryId] = _CachedLength(signature, height);
    return height;
  }

  static double _estimateTitleHeight(String title) {
    const charsPerLine = 28;
    final lines = (title.trim().length / charsPerLine)
        .ceil()
        .clamp(1, 4)
        .toDouble();
    return lines * 30 + 24;
  }
}

class _CachedLength {
  final String signature;
  final double height;

  const _CachedLength(this.signature, this.height);
}
