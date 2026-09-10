import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Keeps text-only HTML blocks in a single selectable text flow.
abstract final class SelectableHtmlCompatibility {
  static const Set<String> _textFlowBlockTags = {
    'p',
    'div',
    'section',
    'article',
    'header',
    'footer',
    'main',
    'aside',
    'figure',
    'figcaption',
    'blockquote',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
  };

  /// Flattens text-only block wrappers while preserving inline markup.
  static String normalizeTextFlow(String html) {
    final fragment = html_parser.parseFragment(html);
    return _normalizeTextFlowNodes(fragment.nodes);
  }

  /// Normalizes model-generated plain text without allowing code-like
  /// sequences such as `<stdatomic.h>` to be parsed as HTML elements.
  static String normalizePlainText(String text) {
    return normalizeTextFlow(htmlEscape.convert(text));
  }

  static String _normalizeTextFlowNodes(Iterable<dom.Node> nodes) {
    final parts = <String>[];
    final inline = StringBuffer();

    void flushInline() {
      final value = inline.toString();
      inline.clear();
      if (value.trim().isNotEmpty) parts.add(value);
    }

    for (final node in nodes) {
      if (node is dom.Text) {
        inline.write(htmlEscape.convert(node.data));
        continue;
      }
      if (node is! dom.Element) continue;

      final tag = node.localName?.toLowerCase();
      if (_textFlowBlockTags.contains(tag)) {
        flushInline();
        final value = _normalizeTextFlowNodes(node.nodes);
        if (value.trim().isNotEmpty) parts.add(value);
      } else {
        inline.write(node.outerHtml);
      }
    }
    flushInline();

    return parts.join('<br><br>');
  }
}
