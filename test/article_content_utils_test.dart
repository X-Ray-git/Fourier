import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:autofolo/utils/article_content_utils.dart';

void main() {
  test('normalizeHtml should remove empty blocks and normalize image src', () {
    const raw = '''
<div style="margin-top: 120px; padding-bottom: 40px;">
  <p>&nbsp;</p>
  <img data-src="//cdn.example.com/a.png" />
</div>
<p><br></p>
''';

    final normalized = ArticleContentUtils.normalizeHtml(raw);
    expect(normalized.contains('&nbsp;'), isFalse);
    expect(normalized.contains('margin-top'), isFalse);
    expect(normalized.contains('https://cdn.example.com/a.png'), isTrue);
  });

  test('normalizeHtml removes nested formatting-only spacer paragraphs', () {
    const raw = '''
<p><span>第一句话。</span></p>
<p><span><br></span></p>
<section><p><strong><span>&nbsp;<br></span></strong></p></section>
<p><span>第二句话。</span></p>
''';

    final fragment = html_parser.parseFragment(
      ArticleContentUtils.normalizeHtml(raw),
    );

    expect(fragment.querySelectorAll('p'), hasLength(2));
    expect(fragment.querySelector('section'), isNull);
    expect(fragment.querySelectorAll('br'), isEmpty);
    expect(fragment.text, contains('第一句话。'));
    expect(fragment.text, contains('第二句话。'));
  });

  test('normalizeHtml preserves empty anchors and media blocks', () {
    const raw = '''
<p id="chapter-anchor"><span><br></span></p>
<section><span name="legacy-anchor"><br></span></section>
<p><span><img src="https://cdn.example.com/content.png"></span></p>
''';

    final fragment = html_parser.parseFragment(
      ArticleContentUtils.normalizeHtml(raw),
    );

    expect(fragment.querySelector('#chapter-anchor'), isNotNull);
    expect(fragment.querySelector('[name="legacy-anchor"]'), isNotNull);
    expect(fragment.querySelector('img'), isNotNull);
  });

  test('extractImageUrls should dedupe and keep valid http/https urls', () {
    const html = '''
<img src="https://a.com/1.png" />
<img data-src="//a.com/1.png" />
<img src="javascript:alert(1)" />
<img src="https://a.com/2.png" />
''';

    final urls = ArticleContentUtils.extractImageUrls(html);
    expect(urls, ['https://a.com/1.png', 'https://a.com/2.png']);
  });

  test('normalizeHtml should safely linkify plain text urls only', () {
    const raw = '''
<p>Read https://example.com/path?a=1&b=2 from AT&T.</p>
<p><a href="https://linked.example/path?a=1&b=2">https://linked.example/path?a=1&b=2</a></p>
<p><code>https://code.example/path?a=1&b=2</code></p>
''';

    final normalized = ArticleContentUtils.normalizeHtml(raw);

    expect(
      normalized,
      contains(
        '<a href="https://example.com/path?a=1&amp;b=2">https://example.com/path?a=1&amp;b=2</a>',
      ),
    );
    expect(normalized, contains('AT&amp;T'));
    expect(
      normalized,
      contains('<code>https://code.example/path?a=1&amp;b=2</code>'),
    );
    expect(RegExp(r'<a[^>]*>\s*<a').hasMatch(normalized), isFalse);
  });

  test('normalizeHtml removes only truly hidden opacity values', () {
    const raw = '''
<p style="opacity: 0.8">半透明但可见</p>
<p style="opacity: 0">完全透明</p>
<p style="opacity: 0.0 !important">仍然完全透明</p>
''';

    final normalized = ArticleContentUtils.normalizeHtml(raw);

    expect(normalized, contains('半透明但可见'));
    expect(normalized, isNot(contains('完全透明')));
    expect(normalized, isNot(contains('仍然完全透明')));
  });

  test('normalizeHtml keeps escaped top-level markup as text', () {
    const raw = '&lt;b&gt;literal&lt;/b&gt;';

    final normalized = ArticleContentUtils.normalizeHtml(raw);

    expect(normalized, '&lt;b&gt;literal&lt;/b&gt;');
  });

  test('flattened layout tables do not turn escaped text into markup', () {
    const raw = '''
<table role="presentation">
  <tr><td>&lt;b&gt;literal&lt;/b&gt;</td></tr>
</table>
''';

    final normalized = ArticleContentUtils.normalizeHtml(raw);

    expect(normalized, '&lt;b&gt;literal&lt;/b&gt;');
    expect(html_parser.parseFragment(normalized).querySelector('b'), isNull);
  });

  test('normalizeHtmlForEntry invalidates cache when raw content changes', () {
    const entryId = 'cache-content-change';

    final first = ArticleContentUtils.normalizeHtmlForEntry(
      entryId,
      '<p>first</p>',
    );
    final second = ArticleContentUtils.normalizeHtmlForEntry(
      entryId,
      '<p>second</p>',
    );

    expect(first, '<p>first</p>');
    expect(second, '<p>second</p>');
    ArticleContentUtils.clearCacheForEntry(entryId);
  });

  test('normalizeHtml preserves stable data tables without th elements', () {
    const raw = '''
<table>
  <tr><td>维度</td><td>模型 A</td><td>模型 B</td></tr>
  <tr><td>命中折扣</td><td>90%</td><td>75%</td></tr>
  <tr><td>缓存寿命</td><td>5 分钟</td><td>1 小时</td></tr>
</table>
''';

    final normalized = ArticleContentUtils.normalizeHtml(raw);
    final table = html_parser.parseFragment(normalized).querySelector('table');

    expect(table, isNotNull);
    expect(table!.querySelectorAll('tr'), hasLength(3));
    expect(table.querySelectorAll('td'), hasLength(9));
  });

  test('normalizeHtml preserves tables with explicit th elements', () {
    const raw = '''
<table>
  <tr><th>名称</th><th>数值</th></tr>
  <tr><td>命中率</td><td>90%</td></tr>
</table>
''';

    final normalized = ArticleContentUtils.normalizeHtml(raw);
    expect(
      html_parser.parseFragment(normalized).querySelector('table'),
      isNotNull,
    );
  });

  test('normalizeHtml flattens single-cell newsletter layout tables', () {
    const raw = '''
<table role="presentation">
  <tr><td><p>Newsletter 正文</p></td></tr>
</table>
''';

    final normalized = ArticleContentUtils.normalizeHtml(raw);
    final fragment = html_parser.parseFragment(normalized);
    expect(fragment.querySelector('table'), isNull);
    expect(fragment.text, contains('Newsletter 正文'));
  });

  test('normalizeHtml flattens irregular non-semantic table layouts', () {
    const raw = '''
<table>
  <tr><td>顶部容器</td></tr>
  <tr><td>左侧</td><td>右侧</td></tr>
  <tr><td>底部容器</td></tr>
</table>
''';

    final normalized = ArticleContentUtils.normalizeHtml(raw);
    final fragment = html_parser.parseFragment(normalized);
    expect(fragment.querySelector('table'), isNull);
    expect(fragment.text, contains('左侧'));
    expect(fragment.text, contains('右侧'));
  });

  test(
    'normalizeHtml unwraps outer layout without damaging nested data table',
    () {
      const raw = '''
<table role="presentation">
  <tr><td>
    <table>
      <tr><th>名称</th><th>数值</th></tr>
      <tr><td>命中率</td><td>90%</td></tr>
    </table>
  </td></tr>
</table>
''';

      final normalized = ArticleContentUtils.normalizeHtml(raw);
      final fragment = html_parser.parseFragment(normalized);
      final tables = fragment.querySelectorAll('table');
      expect(tables, hasLength(1));
      expect(tables.single.querySelectorAll('tr'), hasLength(2));
      expect(tables.single.querySelectorAll('th'), hasLength(2));
    },
  );

  test(
    'readability keeps supported video embeds and removes other iframes',
    () {
      final document = html_parser.parse('''
<article>
  <p>This paragraph contains enough useful article text to become a readability candidate.</p>
  <iframe src="https://www.youtube-nocookie.com/embed/sH6mlUzAMzU"></iframe>
  <iframe src="https://player.bilibili.com/player.html?bvid=BV1ZiM86BEwu&amp;autoplay=false"></iframe>
  <iframe src="https://tracking.example.com/widget"></iframe>
  <p>Another substantial paragraph keeps the selected article container stable for this test.</p>
</article>
''');

      final content = ArticleContentUtils.getReadabilityContent(document);
      expect(content, isNotNull);
      expect(content!.outerHtml, contains('youtube-nocookie.com/embed'));
      expect(content.outerHtml, contains('player.bilibili.com/player.html'));
      expect(content.outerHtml, isNot(contains('tracking.example.com')));
    },
  );
}
