import 'package:flutter_test/flutter_test.dart';

import 'package:autofolo/models/article.dart';

void main() {
  test('fromEntryJson should parse nested entry/feed fields', () {
    final article = ArticleModel.fromEntryJson({
      'entries': {
        'id': 'e-1',
        'title': 'Hello',
        'url': 'https://example.com',
        'publishedAt': '2026-01-01T00:00:00.000Z',
        'read': false,
        'author': 'Tester',
        'media': [
          {'url': 'https://example.com/a.png'},
        ],
      },
      'feeds': {'id': 'f-1', 'title': 'FeedA'},
    }, subscriptionCategory: 'Tech');

    expect(article.entryId, 'e-1');
    expect(article.feedId, 'f-1');
    expect(article.feedTitle, 'FeedA');
    expect(article.subscriptionCategory, 'Tech');
    expect(article.imageUrl, 'https://example.com/a.png');
  });

  test(
    'fromEntryJson should decode text entities without touching html content',
    () {
      final article = ArticleModel.fromEntryJson({
        'entries': {
          'id': 'e-2',
          'title': 'OpenClaw &amp; DeepSeek',
          'url': 'https://example.com?a=1&amp;b=2',
          'content': '<p>OpenClaw &amp; DeepSeek</p>',
          'author': 'A &amp; B',
        },
        'feeds': {'id': 'f-2', 'title': 'AI &amp; Tools'},
      }, subscriptionCategory: 'News &amp; Analysis');

      expect(article.title, 'OpenClaw & DeepSeek');
      expect(article.feedTitle, 'AI & Tools');
      expect(article.author, 'A & B');
      expect(article.subscriptionCategory, 'News & Analysis');
      expect(article.url, 'https://example.com?a=1&amp;b=2');
      expect(article.content, '<p>OpenClaw &amp; DeepSeek</p>');
    },
  );

  test('fromCache decodes legacy text entities without touching content', () {
    final article = ArticleModel.fromCache({
      'entryId': 'e-cache',
      'feedTitle': 'AI &amp; Tools',
      'title': 'OpenClaw&ensp;Companion',
      'subscriptionCategory': 'News &amp; Analysis',
      'author': 'A &amp; B',
      'filterReason': 'Low&ensp;value',
      'url': 'https://example.com?a=1&amp;b=2',
      'content': '<p>A &ensp; B</p>',
    });

    expect(article.title, 'OpenClaw Companion');
    expect(article.feedTitle, 'AI & Tools');
    expect(article.subscriptionCategory, 'News & Analysis');
    expect(article.author, 'A & B');
    expect(article.filterReason, 'Low value');
    expect(article.url, 'https://example.com?a=1&amp;b=2');
    expect(article.content, '<p>A &ensp; B</p>');
  });

  test('userAction survives cache round trip and defaults to null', () {
    final article = ArticleModel(
      entryId: 'e-ua',
      feedId: 'f',
      feedTitle: 'F',
      title: 'T',
      url: 'u',
      userAction: ArticleModel.userActionMisclassifySpam,
    );

    expect(article.toJson()['userAction'], 'n_spam');
    expect(
      ArticleModel.fromCache(article.toJson()).userAction,
      ArticleModel.userActionMisclassifySpam,
    );
    expect(
      ArticleModel.fromEntryJson(<String, dynamic>{
        'entries': <String, dynamic>{'id': 'x'},
        'feeds': <String, dynamic>{},
      }).userAction,
      isNull,
    );
    expect(ArticleModel.fromCache({}).userAction, isNull);
  });
}
