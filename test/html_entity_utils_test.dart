import 'package:autofolo/utils/html_entity_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodeText decodes common named and numeric entities', () {
    expect(
      HtmlEntityUtils.decodeText(
        'OpenClaw &amp; DeepSeek &#8211; &quot;fast&quot;',
      ),
      'OpenClaw & DeepSeek \u2013 "fast"',
    );
    expect(HtmlEntityUtils.decodeText('A &#x26; B'), 'A & B');
    expect(HtmlEntityUtils.decodeText('A &ndash; B'), 'A \u2013 B');
  });

  test(
    'decodeText keeps non-entity text and literal angle brackets intact',
    () {
      expect(HtmlEntityUtils.decodeText('A < B && C > D'), 'A < B && C > D');
    },
  );
}
