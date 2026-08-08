import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fourier/models/article.dart';
import 'package:fourier/pages/widgets/article_card.dart';

void main() {
  testWidgets('ArticleCard renders when local AI caches are not hydrated', (
    tester,
  ) async {
    final article = ArticleModel(
      entryId: 'entry-1',
      feedId: 'feed-1',
      feedTitle: 'Feed',
      feedImage: null,
      title: 'A long article title that should wrap without layout errors',
      url: 'https://example.com',
      content: '<p>Hello</p>',
      publishedAt: '2026-06-02T00:00:00.000Z',
      category: 'feeds',
      subscriptionCategory: 'Very Long Category Name',
      author: 'Author',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ArticleCard(article: article)),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('A long article title'), findsOneWidget);
  });
}
