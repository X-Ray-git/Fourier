import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:fourier/utils/article_content_utils.dart';

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

  test('normalizeHtml resolves relative images against the article URL', () {
    const raw = '''
<img src="/assets/diagram.svg" alt="Diagram">
<img src="../shared/photo.webp" alt="Photo">
''';

    final fragment = html_parser.parseFragment(
      ArticleContentUtils.normalizeHtml(
        raw,
        sourceUrl: 'https://addyosmani.com/blog/software-factories/',
      ),
    );

    expect(
      fragment.querySelectorAll('img').map((image) => image.attributes['src']),
      [
        'https://addyosmani.com/assets/diagram.svg',
        'https://addyosmani.com/blog/shared/photo.webp',
      ],
    );
  });

  test('normalizeHtml keeps unresolved relative images without a base URL', () {
    const raw = '<img src="/assets/diagram.svg" alt="Diagram">';

    final normalized = ArticleContentUtils.normalizeHtml(raw);

    expect(normalized, contains('src="/assets/diagram.svg"'));
    expect(ArticleContentUtils.extractImageUrls(normalized), isEmpty);
  });

  test('MarkTechPost compatibility removes inert code-copy controls', () {
    const raw = '''
<div>
  <a id="user-content-dm-copy-raw-code"><span>Copy Code</span></a>
  <pre><code>print('hello')</code></pre>
</div>
''';

    final normalized = ArticleContentUtils.normalizeHtml(
      raw,
      sourceUrl: 'https://www.marktechpost.com/example/',
    );

    expect(normalized, isNot(contains('Copy Code')));
    expect(normalized, contains("print('hello')"));
  });

  test('MarkTechPost compatibility replaces a leaked interactive document', () {
    const raw = '''
<p>Article body</p>
<h2>Interactive Explainer</h2>
<title>Demo — Interactive Explainer</title>
<div><h1>Leaked app title</h1><p>Leaked controls</p></div>
''';

    final normalized = ArticleContentUtils.normalizeHtml(
      raw,
      sourceUrl: 'https://www.marktechpost.com/example/',
    );

    expect(normalized, contains('Article body'));
    expect(normalized, contains('交互内容仅在原文网页中可用'));
    expect(normalized, contains('https://www.marktechpost.com/example/'));
    expect(normalized, isNot(contains('Leaked app title')));
    expect(normalized, isNot(contains('Leaked controls')));
  });

  test('MarkTechPost rules do not affect another source', () {
    const raw = '''
<a id="user-content-dm-copy-raw-code">Copy Code</a>
<h2>Interactive Explainer</h2><title>Embedded demo</title><p>Demo</p>
''';

    final normalized = ArticleContentUtils.normalizeHtml(
      raw,
      sourceUrl: 'https://example.com/article',
    );

    expect(normalized, contains('Copy Code'));
    expect(normalized, contains('Demo'));
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

  test('normalizeHtml converts a Hugging Face byline to compact authors', () {
    const raw = '''
<div data-target="BlogAuthorsByline">
  <div>
    <a href="/jane">
      <img class="rounded-full! size-12" alt="Jane Doe's avatar"
           src="https://cdn-avatars.huggingface.co/v1/uploads/jane.png">
    </a>
    <span class="fullname">Jane Doe</span>
  </div>
</div>
<p><img src="https://huggingface.co/datasets/docs/article-image.png"></p>
''';

    final fragment = html_parser.parseFragment(
      ArticleContentUtils.normalizeHtml(raw),
    );

    final authorList = fragment.querySelector('fourier-author-list');
    final author = authorList?.querySelector('fourier-author');
    expect(authorList, isNotNull);
    expect(author?.attributes['name'], 'Jane Doe');
    expect(author?.attributes['handle'], 'jane');
    expect(author?.attributes['profile'], 'https://huggingface.co/jane');
    expect(
      author?.attributes['avatar'],
      'https://cdn-avatars.huggingface.co/v1/uploads/jane.png',
    );
    expect(fragment.querySelectorAll('img'), hasLength(1));
    expect(
      fragment.querySelector('img')!.attributes['src'],
      'https://huggingface.co/datasets/docs/article-image.png',
    );
  });

  test('normalizeHtml removes empty Hugging Face avatar stacks', () {
    const raw = '''
<ul>
  <li><a href="/one"><img class="rounded-full" src="https://cdn-avatars.huggingface.co/v1/one.png"></a></li>
  <li><a href="/two"><img class="rounded-full" src="https://cdn-avatars.huggingface.co/v1/two.png"></a></li>
</ul>
<p>正文</p>
''';

    final fragment = html_parser.parseFragment(
      ArticleContentUtils.normalizeHtml(raw),
    );

    expect(fragment.querySelector('ul'), isNull);
    expect(fragment.querySelectorAll('img'), isEmpty);
    expect(fragment.text, contains('正文'));
  });

  test('normalizeHtml keeps avatar-like images from unrelated sources', () {
    const raw = '''
<p><img class="rounded-full" alt="Demo avatar"
        src="https://example.com/avatar.png"></p>
''';

    final fragment = html_parser.parseFragment(
      ArticleContentUtils.normalizeHtml(raw),
    );

    expect(fragment.querySelector('img'), isNotNull);
  });

  test('normalizeHtml keeps non-avatar images from the avatar CDN', () {
    const raw = '''
<figure><img alt="Model comparison chart"
  src="https://cdn-avatars.huggingface.co/v1/chart.png"></figure>
''';

    final fragment = html_parser.parseFragment(
      ArticleContentUtils.normalizeHtml(raw),
    );

    expect(fragment.querySelector('img'), isNotNull);
  });

  test('normalizeHtml removes semantic relative Hugging Face avatars', () {
    const raw = '''
<div><img class="rounded-full! size-9" alt="Jane's avatar"
          src="/avatars/jane.svg"><span>Jane Doe</span></div>
''';

    final fragment = html_parser.parseFragment(
      ArticleContentUtils.normalizeHtml(raw),
    );

    expect(fragment.querySelector('img'), isNull);
    expect(fragment.text, contains('Jane Doe'));
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

  test('CoderBill compatibility removes Circle email chrome and styles', () {
    const raw = '''
<table id="user-content-bodyTable" role="presentation">
  <tr><td>
    <h2 style="font-size: 30px">邮件标题</h2>
    <p style="margin: 24px">邮件正文</p>
    <p><a href="https://email.notification.circle.so/c/post"
      style="height: 38px; line-height: 39px; padding: 0 20px; background: blue">View post</a></p>
    <img src="https://example.com/content.png"
      style="width: 320px; height: 180px; border-radius: 8px">
    <h3>Get the Circle app</h3>
    <a href="https://email.notification.circle.so/c/app">
      <img width="140" height="47"
        src="https://cdn.mcauto-images-production.sendgrid.net/assets/498x167.png">
    </a>
    <table>
      <tr><th>名称</th><th>数值</th></tr>
      <tr><td>命中率</td><td>90%</td></tr>
    </table>
    <table role="presentation"><tr><td>
      <a href="https://email.notification.circle.so/c/settings">Change notification settings</a>
      <a href="https://email.notification.circle.so/c/unsubscribe">Unsubscribe from all emails</a>
    </td></tr></table>
  </td></tr>
</table>
''';

    final normalized = ArticleContentUtils.normalizeHtml(
      raw,
      feedId: 'coderbill',
      category: 'inbox',
    );
    final fragment = html_parser.parseFragment(normalized);

    expect(fragment.text, contains('邮件正文'));
    expect(fragment.text, contains('View post'));
    expect(fragment.text, isNot(contains('Get the Circle app')));
    expect(fragment.text, isNot(contains('Change notification settings')));
    expect(fragment.text, isNot(contains('Unsubscribe from all emails')));
    final contentImage = fragment.querySelector('img');
    expect(contentImage?.attributes['src'], 'https://example.com/content.png');
    expect(contentImage?.attributes['width'], '320');
    expect(contentImage?.attributes['height'], '180');
    expect(contentImage?.attributes.containsKey('style'), isFalse);
    expect(fragment.querySelectorAll('table'), hasLength(1));
    expect(fragment.querySelector('table th')?.text, '名称');
    expect(normalized, isNot(contains('height: 38px')));
    expect(
      fragment
          .querySelector('a[data-fourier-email-action="primary"]')
          ?.attributes['href'],
      'https://email.notification.circle.so/c/post',
    );
  });

  test('CoderBill rules require both source identity and Circle structure', () {
    const circleTemplate = '''
<table id="user-content-emailBody" role="presentation">
  <tr><td><a href="https://email.notification.circle.so/c/post"
    style="height: 38px">正文</a></td></tr>
</table>
''';
    const unrelated = '<a style="height: 38px">普通正文</a>';

    final otherInbox = ArticleContentUtils.normalizeHtml(
      circleTemplate,
      feedId: 'another-inbox',
      category: 'inbox',
    );
    final ordinaryCoderBill = ArticleContentUtils.normalizeHtml(
      unrelated,
      feedId: 'coderbill',
      category: 'inbox',
    );

    expect(otherInbox, contains('height: 38px'));
    expect(ordinaryCoderBill, contains('height: 38px'));
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
