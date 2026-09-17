import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:fourier/utils/article_content_utils.dart';
import 'package:fourier/utils/html_chunk_parser.dart';

// Synthetic legacy layout; no real article content is stored in the fixture.
const _legacyPage = '''
<html><head><title>Example Essay</title></head><body>
<table><tr>
  <td><a href="index.html">Site navigation</a></td>
  <td><img src="masthead.gif" alt="Site masthead">
    <table><tr><td width="435">
      <img src="essay.gif" alt="Example Essay"><br><br>
      <font size="2" face="verdana">September 2026<br><br>
        The first paragraph contains substantial prose and an
        <a href="https://example.com/source">ordinary link</a>.<br><br>
        The second paragraph contains <b>important text</b> and a
        <a href="#note1">footnote reference</a>.<br><br>
        <a id="note1">1.</a> The complete footnote is preserved.
        <script>unwantedScript()</script>
        <iframe src="https://tracking.example.com/widget"></iframe>
      </font>
    </td></tr></table>
  </td>
</tr></table>
</body></html>
''';

void main() {
  test(
    'legacy essay extraction preserves prose and notes without site chrome',
    () {
      final content = ArticleContentUtils.getReadabilityContent(
        html_parser.parse(_legacyPage),
        sourceUrl: 'https://paulgraham.com/example.html',
      );

      expect(content, isNotNull);
      expect(content!.text, contains('The first paragraph'));
      expect(content.text, contains('The second paragraph'));
      expect(content.text, contains('The complete footnote is preserved.'));
      expect(
        content.querySelector('a[href="https://example.com/source"]'),
        isNotNull,
      );
      expect(content.querySelector('a[href="#note1"]'), isNotNull);
      expect(content.querySelector('#note1'), isNotNull);
      expect(content.querySelector('b')?.text, 'important text');
      expect(content.text, isNot(contains('Site navigation')));
      expect(content.querySelector('img, script, iframe'), isNull);

      final normalized = ArticleContentUtils.normalizeHtml(content.outerHtml);
      final chunks = HtmlChunkParser.parseSync(normalized);
      expect(chunks, isNotEmpty);
      final rendered = chunks.map((chunk) => chunk.content).join();
      expect(rendered, contains('The first paragraph'));
      expect(rendered, contains('The complete footnote is preserved.'));
    },
  );

  test('legacy fallback requires the exact source host', () {
    for (final url in [
      null,
      'https://example.com/example.html',
      'https://paulgraham.com.example.com/example.html',
    ]) {
      expect(
        ArticleContentUtils.getReadabilityContent(
          html_parser.parse(_legacyPage),
          sourceUrl: url,
        ),
        isNull,
      );
    }
    expect(
      ArticleContentUtils.getReadabilityContent(
        html_parser.parse(_legacyPage),
        sourceUrl: 'https://www.paulgraham.com/example.html',
      ),
      isNotNull,
    );
  });

  test('legacy fallback requires the essay title image and body structure', () {
    for (final raw in [
      _legacyPage.replaceFirst('alt="Example Essay"', 'alt="Other page"'),
      _legacyPage.replaceFirst('<title>Example Essay</title>', ''),
      _legacyPage.replaceFirst('face="verdana"', 'face="other"'),
      _legacyPage.replaceAll('<br>', ''),
      '<title>Example Essay</title><table><tr><td>'
          '<img alt="Example Essay"><font size="2" face="verdana">'
          'Short<br><br></font></td></tr></table>',
    ]) {
      expect(
        ArticleContentUtils.getReadabilityContent(
          html_parser.parse(raw),
          sourceUrl: 'https://paulgraham.com/example.html',
        ),
        isNull,
      );
    }
  });

  test('normal paragraph extraction still takes precedence', () {
    final document = html_parser.parse(_legacyPage);
    document.body!.append(
      html_parser.parseFragment('''
<div><p>This modern paragraph is long enough to be selected by normal scoring.</p>
<p>A second substantial paragraph reinforces the existing article candidate.</p></div>
'''),
    );
    final content = ArticleContentUtils.getReadabilityContent(
      document,
      sourceUrl: 'https://paulgraham.com/example.html',
    );
    expect(content!.localName, 'div');
    expect(content.text, contains('This modern paragraph'));
  });
}
