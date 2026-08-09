import 'package:flutter_test/flutter_test.dart';

import 'package:fourier/models/article.dart';

void main() {
  test('copyWith preserves fields that are not provided', () {
    final original = ArticleModel(
      entryId: 'entry-1',
      feedId: 'feed-1',
      feedTitle: 'Feed',
      feedImage: 'https://example.com/feed.png',
      title: 'Title',
      url: 'https://example.com/article',
      content: '<p>Body</p>',
      author: 'Author',
      imageUrl: 'https://example.com/image.png',
      filterReason: 'Reason',
      filteredAt: 123,
      userAction: ArticleModel.userActionKeep,
    );

    final updated = original.copyWith(isRead: true);

    expect(updated.isRead, isTrue);
    expect(updated.feedImage, original.feedImage);
    expect(updated.content, original.content);
    expect(updated.author, original.author);
    expect(updated.imageUrl, original.imageUrl);
    expect(updated.filterReason, original.filterReason);
    expect(updated.filteredAt, original.filteredAt);
    expect(updated.userAction, original.userAction);
  });

  test('copyWith can explicitly clear nullable fields', () {
    final original = ArticleModel(
      entryId: 'entry-1',
      feedId: 'feed-1',
      feedTitle: 'Feed',
      feedImage: 'https://example.com/feed.png',
      title: 'Title',
      url: 'https://example.com/article',
      content: '<p>Body</p>',
      author: 'Author',
      imageUrl: 'https://example.com/image.png',
      filterReason: 'Reason',
      filteredAt: 123,
      userAction: ArticleModel.userActionKeep,
    );

    final updated = original.copyWith(
      feedImage: null,
      content: null,
      author: null,
      imageUrl: null,
      filterReason: null,
      filteredAt: null,
      userAction: null,
    );

    expect(updated.feedImage, isNull);
    expect(updated.content, isNull);
    expect(updated.author, isNull);
    expect(updated.imageUrl, isNull);
    expect(updated.filterReason, isNull);
    expect(updated.filteredAt, isNull);
    expect(updated.userAction, isNull);
  });

  test('fromEntryJson should parse nested entry/feed fields', () {
    final article = ArticleModel.fromEntryJson({
      'read': true,
      'entries': {
        'id': 'e-1',
        'title': 'Hello',
        'url': 'https://example.com',
        'publishedAt': '2026-01-01T00:00:00.000Z',
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
    expect(article.isRead, isTrue);
  });

  test('fromInboxJson reads status from the list item envelope', () {
    final article = ArticleModel.fromInboxJson({
      'read': true,
      'entries': {
        'id': 'inbox-entry',
        'title': 'Inbox item',
        'url': 'https://example.com/inbox',
      },
      'feeds': {'id': 'inbox-source', 'title': 'Inbox'},
    });

    expect(article.entryId, 'inbox-entry');
    expect(article.isRead, isTrue);
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
