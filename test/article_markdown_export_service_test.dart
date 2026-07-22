import 'package:autofolo/models/article.dart';
import 'package:autofolo/services/article_markdown_export_service.dart';
import 'package:autofolo/utils/html_chunk_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ArticleModel article({
    String id = '1',
    String title = 'Article title',
    String? content,
    String feedTitle = 'Example Feed',
    String? author = 'Author',
    String publishedAt = '2026-07-19T00:00:00.000Z',
  }) {
    return ArticleModel(
      entryId: id,
      feedId: 'feed-$id',
      feedTitle: feedTitle,
      title: title,
      url: 'https://example.com/$id',
      content: content,
      publishedAt: publishedAt,
      author: author,
    );
  }

  test(
    'single export removes a duplicate leading title and keeps metadata',
    () {
      final markdown = ArticleMarkdownExportService.buildArticle(
        article: article(title: 'Repeated title'),
        chunks: const [
          HtmlChunk(
            type: HtmlChunkType.heading,
            content: 'Repeated title',
            headingLevel: 1,
          ),
          HtmlChunk(type: HtmlChunkType.paragraph, content: '<p>Body</p>'),
        ],
      );

      expect(
        RegExp(r'^# Repeated title$', multiLine: true).allMatches(markdown),
        hasLength(1),
      );
      expect(markdown, contains('> 来源：Example Feed'));
      expect(markdown, contains('> 作者：Author'));
      expect(markdown, contains('> 发布：2026-07-19T00:00:00.000Z'));
      expect(markdown, contains('> 原文：https://example.com/1'));
      expect(markdown, contains('Body'));
    },
  );

  test(
    'single export renders tables, lists, code blocks and escaped links',
    () {
      final markdown = ArticleMarkdownExportService.buildArticle(
        article: article(),
        chunks: const [
          HtmlChunk(
            type: HtmlChunkType.table,
            content:
                '<table><tr><th>Name</th><th>Value</th></tr>'
                '<tr><td>A</td><td>1 | 2</td></tr></table>',
          ),
          HtmlChunk(
            type: HtmlChunkType.list,
            content: '<ol><li>First</li><li>Second</li></ol>',
          ),
          HtmlChunk(type: HtmlChunkType.codeBlock, content: 'final value = 1;'),
          HtmlChunk(
            type: HtmlChunkType.paragraph,
            content: '<p><a href="https://example.com/docs">A [link]</a></p>',
          ),
        ],
      );

      expect(markdown, contains('| Name | Value |'));
      expect(markdown, contains('| A | 1 \\| 2 |'));
      expect(markdown, contains('1. First\n2. Second'));
      expect(markdown, contains('```\nfinal value = 1;\n```'));
      expect(markdown, contains(r'[A \[link\]](https://example.com/docs)'));
    },
  );

  test('batch export keeps article order without a batch heading', () async {
    final markdown = await ArticleMarkdownExportService.buildBatch([
      article(id: '1', title: 'First', content: '<p>First body</p>'),
      article(id: '2', title: 'Second', content: '<p>Second body</p>'),
    ]);

    expect(markdown, isNot(contains('# 静默订阅源导出')));
    expect(markdown.indexOf('# First'), lessThan(markdown.indexOf('# Second')));
    expect(markdown, contains('First body'));
    expect(markdown, contains('\n\n---\n\n# Second'));
  });

  test('batch export keeps metadata when the body is unavailable', () async {
    final markdown = await ArticleMarkdownExportService.buildBatch([
      article(id: '1', title: 'Missing body'),
    ]);

    expect(markdown, contains('# Missing body'));
    expect(markdown, contains('> 原文：https://example.com/1'));
    expect(markdown, contains('> 正文尚未缓存'));
  });

  test('malformed wrapped lists do not recurse indefinitely', () {
    final markdown = ArticleMarkdownExportService.buildArticle(
      article: article(),
      chunks: const [
        HtmlChunk(
          type: HtmlChunkType.list,
          content: '<ul><div><li>Wrapped item</li></div></ul>',
        ),
        HtmlChunk(
          type: HtmlChunkType.list,
          content: '<ul><div>Text without a list item</div></ul>',
        ),
      ],
    );

    expect(markdown, contains('- Wrapped item'));
    expect(markdown, contains('Text without a list item'));
  });

  test('single article export can run off the UI isolate', () async {
    final markdown = await ArticleMarkdownExportService.buildArticleAsync(
      article: article(title: 'Async export'),
      chunks: const [
        HtmlChunk(type: HtmlChunkType.paragraph, content: '<p>Body</p>'),
      ],
    );

    expect(markdown, contains('# Async export'));
    expect(markdown, contains('Body'));
  });
}
