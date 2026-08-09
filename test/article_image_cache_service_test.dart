import 'package:fourier/services/article_image_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArticleImageCacheService', () {
    test('builds an article-ordered plan with a per-article limit', () {
      final firstImages = List.generate(
        10,
        (index) => '<img src="https://example.com/first-$index.jpg">',
      ).join();
      final plan = ArticleImageCacheService.buildPrefetchPlan([
        {'articleId': 'first', 'content': firstImages},
        {
          'articleId': 'second',
          'content': '<img src="https://example.com/second.jpg">',
        },
      ]);

      expect(plan, hasLength(9));
      expect(plan.take(8).map((item) => item['articleId']).toSet(), {'first'});
      expect(plan.last, {
        'articleId': 'second',
        'imageUrl': 'https://example.com/second.jpg',
      });
    });

    test('skips obvious animated images during background prefetch', () {
      final plan = ArticleImageCacheService.buildPrefetchPlan([
        {
          'articleId': 'entry',
          'content': '''
            <img src="https://example.com/animated.gif">
            <img src="https://example.com/animated.apng">
            <img src="https://example.com/image?id=1&format=gif">
            <img src="https://example.com/static.webp">
          ''',
        },
      ]);

      expect(plan, [
        {'articleId': 'entry', 'imageUrl': 'https://example.com/static.webp'},
      ]);
    });

    test('resolves relative images before building the prefetch plan', () {
      final plan = ArticleImageCacheService.buildPrefetchPlan([
        {
          'articleId': 'entry',
          'sourceUrl': 'https://addyosmani.com/blog/software-factories/',
          'content': '<img src="/assets/diagram.svg">',
        },
      ]);

      expect(plan, [
        {
          'articleId': 'entry',
          'imageUrl': 'https://addyosmani.com/assets/diagram.svg',
        },
      ]);
    });

    test('limits Android-style background plans by article count', () {
      final articles = List.generate(
        60,
        (index) => {
          'articleId': 'entry-$index',
          'content': '<img src="https://example.com/$index.jpg">',
        },
      );

      final plan = ArticleImageCacheService.buildPrefetchPlan(
        articles,
        maxImages: ArticleImageCacheService.androidImagesPerArticle,
        maxArticles: ArticleImageCacheService.androidBackgroundArticleLimit,
      );

      expect(plan, hasLength(50));
      expect(plan.first['articleId'], 'entry-0');
      expect(plan.last['articleId'], 'entry-49');
    });

    test('isolates cache keys by article and derives resized keys', () {
      const url = 'https://example.com/image.jpg';
      final first = ArticleImageCacheService.cacheKey('first', url);
      final second = ArticleImageCacheService.cacheKey('second', url);

      expect(first, isNot(second));
      expect(
        ArticleImageCacheService.resizedCacheKey(first, width: 1440),
        'resized_w1440_$first',
      );
    });

    test('article prefixes cannot overlap when IDs contain separators', () {
      final shortPrefix = ArticleImageCacheService.cacheKeyPrefixForArticle(
        'entry',
      );
      final nestedKey = ArticleImageCacheService.cacheKey(
        'entry:child',
        'https://example.com/image.jpg',
      );

      expect(nestedKey.startsWith(shortPrefix), isFalse);
    });
  });
}
