import 'package:flutter_test/flutter_test.dart';

import 'package:fourier/utils/selectable_html_compatibility.dart';

void main() {
  test('plain text keeps code-like angle brackets visible', () {
    expect(
      SelectableHtmlCompatibility.normalizePlainText(
        '默认单线程，可用 <threads.h>，然后继续介绍 <stdatomic.h>。',
      ),
      '默认单线程，可用 &lt;threads.h&gt;，然后继续介绍 '
      '&lt;stdatomic.h&gt;。',
    );
  });
}
