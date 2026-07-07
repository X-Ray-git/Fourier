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
}
