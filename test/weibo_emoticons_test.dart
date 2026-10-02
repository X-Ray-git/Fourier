import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:fourier/models/article.dart';
import 'package:fourier/services/article_markdown_export_service.dart';
import 'package:fourier/utils/article_content_compatibility.dart';
import 'package:fourier/utils/article_content_utils.dart';
import 'package:fourier/utils/article_inline_icon.dart';
import 'package:fourier/utils/html_chunk_parser.dart';
import 'package:fourier/utils/source_rules/weibo_emoticon_data.dart';
import 'package:fourier/utils/source_rules/weibo_emoticons.dart';

void main() {
  const source = 'https://weibo.com/123/Abc';
  String display(String html, {String? url = source}) =>
      ArticleContentCompatibility.forDisplay(html, sourceUrl: url);

  test('only exact Weibo article hosts enable display rules', () {
    for (final url in [source, 'https://m.weibo.cn/detail/123']) {
      expect(WeiboEmoticons.appliesTo(url), isTrue);
    }
    for (final url in [
      null,
      'https://example.com/?url=$source',
      'https://weibo.com.example.com/123',
      'https://example.com/weibo.com',
    ]) {
      const original = '<p>[doge]</p>';
      expect(display(original, url: url), original);
    }
  });

  test('known names become inline icons while unknown text is retained', () {
    const original = '<p>前[doge][未知的新表情][嘻嘻]后 &amp; [赞]</p>';
    final fragment = html_parser.parseFragment(display(original));
    final icons = fragment.querySelectorAll(articleInlineIconTag);
    expect(icons.map((icon) => icon.text), ['[doge]', '[嘻嘻]', '[赞]']);
    expect(fragment.text, '前[doge][未知的新表情][嘻嘻]后 & [赞]');
    expect(icons.first.attributes['src'], weiboEmoticonUrls['[doge]']);
    expect(fragment.querySelectorAll('img'), isEmpty);
    expect(display(display(original)), display(original));
    expect(display('<p>[未知的新表情]</p>'), '<p>[未知的新表情]</p>');
  });

  test('code, links, attributes and other non-prose nodes are unchanged', () {
    const original =
        '<p title="[doge]">正文[doge]</p>'
        '<a href="https://example.com/[doge]">[doge]</a>'
        '<pre>[doge]</pre><code>[doge]</code><kbd>[doge]</kbd>'
        '<samp>[doge]</samp><textarea>[doge]</textarea>'
        '<script>const s="[doge]";</script><style>/*[doge]*/</style>';
    final fragment = html_parser.parseFragment(display(original));
    expect(fragment.querySelectorAll(articleInlineIconTag), hasLength(1));
    expect(fragment.querySelector('p')!.attributes['title'], '[doge]');
    expect(fragment.querySelector('a')!.innerHtml, '[doge]');
    expect(
      fragment.querySelector('a')!.attributes['href'],
      'https://example.com/[doge]',
    );
    for (final tag in [
      'pre',
      'code',
      'kbd',
      'samp',
      'textarea',
      'script',
      'style',
    ]) {
      expect(fragment.querySelector(tag)!.innerHtml, contains('[doge]'));
    }
  });

  test(
    'new official names, traditional names and historical aliases coexist',
    () {
      for (final label in ['[流浪地球2]', '[泪奔]', '[皱眉]', '[点赞]', '[淚]']) {
        expect(weiboEmoticonUrls, contains(label));
      }
      expect(weiboEmoticonUrls.length, 938);
      expect(
        weiboEmoticonUrls.values.every((url) => url.startsWith('https://')),
        isTrue,
      );
      // The new official spelling wins over an older alias source.
      expect(weiboEmoticonUrls['[doge]'], contains('2018new_doge02_org.png'));
    },
  );

  test('official emoji img stays inline and normal photo stays a photo', () {
    const original =
        '<p>前<img alt="[doge]" '
        'src="//face.t.sinajs.cn/t4/appstyle/expression/ext/normal/a1/doge.png">后</p>'
        '<img alt="照片" src="https://example.com/photo.jpg">';
    final chunks = HtmlChunkParser.parseSync(original, sourceUrl: source);
    expect(chunks.map((chunk) => chunk.type), [
      HtmlChunkType.paragraph,
      HtmlChunkType.image,
    ]);
    expect(chunks.first.content, contains(articleInlineIconTag));
    expect(chunks.first.content, contains('https://face.t.sinajs.cn/'));
    expect(chunks.last.imageSrc, 'https://example.com/photo.jpg');
    expect(ArticleContentUtils.extractImageUrls(display(original)), [
      'https://example.com/photo.jpg',
    ]);
  });

  test(
    'normalization and image extraction do not introduce emoji into AI input',
    () {
      final normalized = ArticleContentUtils.normalizeHtml(
        '<p>正文[doge]</p><img src="https://example.com/photo.jpg">',
        sourceUrl: source,
      );
      expect(normalized, contains('[doge]'));
      expect(normalized, isNot(contains(articleInlineIconTag)));
      expect(ArticleContentUtils.extractImageUrls(normalized), [
        'https://example.com/photo.jpg',
      ]);
      final chunks = HtmlChunkParser.parseSync(normalized, sourceUrl: source);
      expect(chunks.first.content, contains(articleInlineIconTag));
      final markdown = ArticleMarkdownExportService.buildArticle(
        article: ArticleModel(
          entryId: 'weibo-test',
          feedId: 'weibo-feed',
          feedTitle: '微博',
          title: '标题',
          url: source,
        ),
        chunks: chunks,
      );
      expect(markdown, contains('正文[doge]'));
      expect(markdown, isNot(contains('sinajs.cn')));
      expect(markdown, contains('https://example.com/photo.jpg'));
    },
  );

  test('async and isolate chunk paths apply the same display rules', () async {
    const original =
        '<h2>标题[嘻嘻]</h2><blockquote>引用[doge]</blockquote>'
        '<ul><li>条目[赞]</li></ul>';
    final chunks = await HtmlChunkParser.parse(original, sourceUrl: source);
    expect(chunks.map((chunk) => chunk.type), [
      HtmlChunkType.heading,
      HtmlChunkType.blockquote,
      HtmlChunkType.list,
    ]);
    expect(
      chunks.every((chunk) => chunk.content.contains(articleInlineIconTag)),
      isTrue,
    );
    final large = '<p>${'正文' * (260 * 1024)}[doge]</p>';
    final isolated = await HtmlChunkParser.parse(large, sourceUrl: source);
    expect(isolated.single.content, contains(articleInlineIconTag));
  });
}
