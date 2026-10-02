import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../article_inline_icon.dart';
import 'weibo_emoticon_data.dart';

/// Weibo-specific display repair. Never changes stored/AI/export HTML.
abstract final class WeiboEmoticons {
  static const _hosts = {
    'weibo.com',
    'www.weibo.com',
    'm.weibo.com',
    'weibo.cn',
    'www.weibo.cn',
    'm.weibo.cn',
  };
  static const _excludedTags = {
    'a',
    'pre',
    'code',
    'kbd',
    'samp',
    'script',
    'style',
    'textarea',
    articleInlineIconTag,
  };
  static final _labels = RegExp(r'\[[^\[\]\r\n]{1,40}\]');

  static bool appliesTo(String? sourceUrl) =>
      _hosts.contains(Uri.tryParse(sourceUrl ?? '')?.host.toLowerCase());

  static String forDisplay(String html) {
    if (!html.contains('[') && !html.contains('sinajs.cn')) return html;
    final fragment = html_parser.parseFragment(html);
    var changed = false;

    void visit(dom.Node node) {
      if (node is dom.Element) {
        if (_excludedTags.contains(node.localName)) return;
        // RSS feeds may already preserve official emoji images. Mark them
        // before chunking so they cannot become full-width photo blocks.
        if (node.localName == 'img') {
          final raw = node.attributes['src'] ?? '';
          final uri = Uri.tryParse(raw.startsWith('//') ? 'https:$raw' : raw);
          if ((uri?.host == 'face.t.sinajs.cn' ||
                  uri?.host == 'img.t.sinajs.cn') &&
              (uri?.path.contains('/appstyle/expression/') ?? false)) {
            final label = node.attributes['alt']?.trim() ?? '';
            if (label.isNotEmpty) {
              final url = uri!.replace(scheme: 'https').toString();
              node.replaceWith(_icon(label, url));
              changed = true;
            }
          }
          return;
        }
      }
      if (node is dom.Text) {
        final parent = node.parentNode;
        if (parent == null) return;
        var offset = 0;
        var replaced = false;
        for (final match in _labels.allMatches(node.data)) {
          final label = match.group(0)!;
          final url = weiboEmoticonUrls[label];
          if (url == null) continue;
          if (match.start > offset) {
            parent.insertBefore(
              dom.Text(node.data.substring(offset, match.start)),
              node,
            );
          }
          parent.insertBefore(_icon(label, url), node);
          offset = match.end;
          replaced = true;
        }
        if (replaced) {
          if (offset < node.data.length) {
            parent.insertBefore(dom.Text(node.data.substring(offset)), node);
          }
          node.remove();
          changed = true;
        }
        return;
      }
      for (final child in node.nodes.toList()) {
        visit(child);
      }
    }

    visit(fragment);
    return changed ? fragment.outerHtml : html;
  }

  static dom.Element _icon(String label, String url) =>
      dom.Element.tag(articleInlineIconTag)
        ..attributes['src'] = url
        ..text = label;
}
