import 'package:autofolo/models/feed.dart';
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
