import 'package:flutter_test/flutter_test.dart';

import 'package:fourier/models/article.dart';
import 'package:fourier/utils/article_length_estimator.dart';

void main() {
  ArticleModel article({required String id, String? content}) {
    return ArticleModel(
      entryId: id,
      feedId: 'feed',
      feedTitle: 'Feed',
      title: 'Title',
      url: 'https://example.com/$id',
      content: content,
    );
  }

  test('formats estimated logical-pixel heights compactly', () {
    expect(ArticleLengthEstimator.formatHeight(860), '860 px');
    expect(ArticleLengthEstimator.formatHeight(1000), '1k px');
    expect(ArticleLengthEstimator.formatHeight(4320), '4.3k px');
    expect(ArticleLengthEstimator.formatHeight(12860), '12.9k px');
  });

  test('includes image blocks in the shared rendering-height estimate', () {
    final textOnly = article(id: 'text', content: '<p>Body text</p>');
    final withImage = article(
      id: 'image',
      content:
          '<p>Body text</p>'
          '<img src="https://example.com/image.jpg" width="340" height="340">',
    );

    expect(
      ArticleLengthEstimator.estimateReadingHeight(withImage),
      greaterThan(ArticleLengthEstimator.estimateReadingHeight(textOnly)),
    );
  });

  test('returns a stable estimate for identical article content', () {
    final value = article(
      id: 'stable',
      content: '<h2>Heading</h2><p>Body text</p>',
    );

    expect(
      ArticleLengthEstimator.estimateReadingHeight(value),
      ArticleLengthEstimator.estimateReadingHeight(value),
    );
  });
}
