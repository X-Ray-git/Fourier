import 'package:fourier/models/feed.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromJson should decode title and category entities', () {
    final feed = FeedModel.fromJson({
      'feedId': 'f-1',
      'category': 'AI &amp; Dev',
      'view': 0,
      'feeds': {
        'title': 'ModelScope &amp; PaperWeekly',
        'url': 'https://example.com?a=1&amp;b=2',
      },
    });

    expect(feed.title, 'ModelScope & PaperWeekly');
    expect(feed.category, 'AI & Dev');
    expect(feed.url, 'https://example.com?a=1&amp;b=2');
  });

  test('fromJson should prefer the subscription title over source title', () {
    final feed = FeedModel.fromJson({
      'feedId': 'f-custom',
      'title': 'My AI Feed',
      'category': 'AI',
      'view': 0,
      'feeds': {
        'title': 'Original Feed Title',
        'url': 'https://example.com/feed.xml',
      },
    });

    expect(feed.title, 'My AI Feed');
    expect(feed.customTitle, 'My AI Feed');
    expect(feed.sourceTitle, 'Original Feed Title');
  });

  test('copyWith can clear subscription title and category', () {
    final feed = FeedModel(
      feedId: 'f-copy',
      title: 'Custom',
      sourceTitle: 'Source',
      customTitle: 'Custom',
      category: 'AI',
    );

    final updated = feed.copyWith(clearCustomTitle: true, clearCategory: true);

    expect(updated.title, 'Source');
    expect(updated.customTitle, isNull);
    expect(updated.category, isNull);
  });

  test('fromCache should decode legacy text entities', () {
    final feed = FeedModel.fromCache({
      'feedId': 'f-cache',
      'title': 'AI&ensp;News',
      'category': 'Research &amp; Development',
      'url': 'https://example.com?a=1&amp;b=2',
    });

    expect(feed.title, 'AI News');
    expect(feed.category, 'Research & Development');
    expect(feed.url, 'https://example.com?a=1&amp;b=2');
  });
}
