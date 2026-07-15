import 'dart:collection';
import 'dart:convert';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../services/article_image_service.dart';
import 'youtube_embed_utils.dart';

abstract final class ArticleContentUtils {
  static const int _cacheMax = 200;
  static const HtmlEscape _elementTextEscape = HtmlEscape(
    HtmlEscapeMode.element,
  );
  static final LinkedHashMap<String, _NormalizedHtmlCacheEntry> _cache =
      LinkedHashMap();

  /// 带缓存的 HTML 规范化，避免同一篇被翻译/摘要各解析一次
  static String normalizeHtmlForEntry(String entryId, String rawHtml) {
    final cached = _cache[entryId];
    if (cached != null && cached.rawHtml == rawHtml) {
      return cached.normalizedHtml;
    }

    if (cached == null && _cache.length >= _cacheMax) {
      _cache.remove(_cache.keys.first);
    }
    final normalized = normalizeHtml(rawHtml);
    _cache[entryId] = _NormalizedHtmlCacheEntry(rawHtml, normalized);
    return normalized;
  }

  static void clearCacheForEntry(String entryId) {
    _cache.remove(entryId);
  }

  static const Set<String> _blockTags = {
    'p',
    'div',
    'section',
    'article',
    'figure',
    'figcaption',
  };

  static const Set<String> _mediaTags = {
    'img',
    'video',
    'iframe',
    'table',
    'pre',
    'code',
    'blockquote',
    'ul',
    'ol',
  };

  static final _multipleBrRe = RegExp(
    r'(<br\s*/?>\s*){3,}',
    caseSensitive: false,
  );
  static final _emptyParagraphRe = RegExp(
    r'<p>\s*(?:&nbsp;|\u00A0|<br\s*/?>|\s)*\s*</p>',
    caseSensitive: false,
  );

  static String normalizeHtml(String rawHtml) {
    final normalized = rawHtml.trim();
    if (normalized.isEmpty) return '';

    final fragment = html_parser.parseFragment(normalized);
    _removeUnsafeTags(fragment);
    _removeTrackingPixels(fragment);
    _removeHiddenElements(fragment);
    _normalizeImages(fragment);
    _trimSpacingStyles(fragment);
    _removeEmptyBlocks(fragment);
    _flattenLayoutTables(fragment);
    _autoLinkifyTextNodes(fragment);

    var html = _fragmentToHtml(fragment);
    html = html.replaceAll(_multipleBrRe, '<br><br>');
    html = html.replaceAll(_emptyParagraphRe, '');
    return html.trim();
  }

  static List<String> extractImageUrls(String html) {
    if (html.trim().isEmpty) return const [];
    final fragment = html_parser.parseFragment(html);
    final result = <String>[];
    final seen = <String>{};

    for (final img in fragment.querySelectorAll('img')) {
      final url = imageUrlFromAttributes(img.attributes);
      if (url == null || seen.contains(url)) continue;
      seen.add(url);
      result.add(url);
    }
    return result;
  }

  static String? imageUrlFromAttributes(Map<dynamic, dynamic> attributes) {
    String? pickFirstSrcsetUrl(String? raw) {
      if (raw == null) return null;
      final first = raw.split(',').first.trim();
      if (first.isEmpty) return null;
      return first.split(RegExp(r'\s+')).first.trim();
    }

    final raw =
        (attributes['src'] as String?) ??
        (attributes['data-src'] as String?) ??
        (attributes['data-original'] as String?) ??
        (attributes['data-lazy-src'] as String?) ??
        pickFirstSrcsetUrl(attributes['srcset'] as String?) ??
        pickFirstSrcsetUrl(attributes['data-srcset'] as String?);
    if (raw == null) return null;

    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final normalized = trimmed.startsWith('//') ? 'https:$trimmed' : trimmed;
    return ArticleImageService.toProxiedUrl(normalized);
  }

  static String _fragmentToHtml(dom.DocumentFragment fragment) {
    final buffer = StringBuffer();
    for (final node in fragment.nodes) {
      if (node is dom.Element) {
        buffer.write(node.outerHtml);
      } else if (node is dom.Text) {
        buffer.write(_elementTextEscape.convert(node.data));
      }
    }
    return buffer.toString();
  }

  static void _removeUnsafeTags(dom.DocumentFragment fragment) {
    final selectors = ['script', 'style', 'noscript'];
    for (final selector in selectors) {
      for (final element in fragment.querySelectorAll(selector)) {
        element.remove();
      }
    }
  }

  static void _normalizeImages(dom.DocumentFragment fragment) {
    for (final image in fragment.querySelectorAll('img')) {
      final url = imageUrlFromAttributes(image.attributes);
      if (url == null) continue;
      image.attributes['src'] = url;
    }
  }

  static void _trimSpacingStyles(dom.DocumentFragment fragment) {
    for (final element in fragment.querySelectorAll('*')) {
      if (!_blockTags.contains(element.localName)) continue;

      final style = element.attributes['style'];
      if (style == null || style.trim().isEmpty) continue;

      final kept = style.split(';').map((item) => item.trim()).where((item) {
        final lower = item.toLowerCase();
        return item.isNotEmpty &&
            !lower.startsWith('height') &&
            !lower.startsWith('min-height') &&
            !lower.startsWith('max-height') &&
            !lower.startsWith('margin') &&
            !lower.startsWith('padding');
      }).toList();

      if (kept.isEmpty) {
        element.attributes.remove('style');
      } else {
        element.attributes['style'] = '${kept.join('; ')};';
      }
    }
  }

  static final _whitespaceCollapseRe = RegExp(r'[\u00A0\s]+');

  static void _removeEmptyBlocks(dom.DocumentFragment fragment) {
    bool changed = true;
    while (changed) {
      changed = false;
      for (final element in fragment.querySelectorAll('*')) {
        if (!_blockTags.contains(element.localName)) continue;
        if (_hasMediaChild(element)) continue;

        final text = element.text.replaceAll(_whitespaceCollapseRe, '').trim();
        if (text.isNotEmpty) continue;

        final hasNonBreakChild = element.children.any(
          (child) => child.localName != 'br',
        );
        if (hasNonBreakChild) continue;

        element.remove();
        changed = true;
      }
    }
  }

  static bool _hasMediaChild(dom.Element element) {
    for (final tag in _mediaTags) {
      if (element.querySelector(tag) != null) {
        return true;
      }
    }
    return false;
  }

  /// 扁平化邮件 Newsletter 的表格布局（保留文字、链接、图片），大幅缩减退给 LLM 的正文体积
  static void _flattenLayoutTables(dom.DocumentFragment fragment) {
    final tables = fragment.querySelectorAll('table').toList();
    for (final table in tables) {
      if (_looksLikeDataTable(table)) continue;
      _unwrapElements(_elementsBelongingToTable(table, 'td'));
      _unwrapElements(_elementsBelongingToTable(table, 'tr'));
      _unwrapElements(_elementsBelongingToTable(table, 'thead'));
      _unwrapElements(_elementsBelongingToTable(table, 'tbody'));
      _unwrapElements(_elementsBelongingToTable(table, 'tfoot'));
      _unwrapElements([table]);
    }
  }

  static bool _looksLikeDataTable(dom.Element table) {
    if (table.attributes['role']?.toLowerCase() == 'presentation') return false;
    if (table.querySelector('table') != null) return false;
    if (_elementsBelongingToTable(table, 'th').isNotEmpty) return true;

    final rows = _elementsBelongingToTable(table, 'tr');
    if (rows.length < 2) return false;

    final columnCounts = <int>[];
    var populatedCells = 0;
    var mediaCells = 0;
    var totalCells = 0;

    for (final row in rows) {
      final cells = row.children.where((child) {
        final tag = child.localName?.toLowerCase();
        return tag == 'td' || tag == 'th';
      }).toList();
      if (cells.isEmpty) return false;

      var columnCount = 0;
      for (final cell in cells) {
        final span = int.tryParse(cell.attributes['colspan'] ?? '') ?? 1;
        columnCount += span.clamp(1, 12);
        totalCells++;
        if (cell.text.trim().isNotEmpty) populatedCells++;
        if (cell.querySelector('img, video, iframe, table') != null) {
          mediaCells++;
        }
      }
      columnCounts.add(columnCount);
    }

    final widest = columnCounts.reduce((a, b) => a > b ? a : b);
    if (widest < 2) return false;

    final frequencies = <int, int>{};
    for (final count in columnCounts) {
      frequencies[count] = (frequencies[count] ?? 0) + 1;
    }
    final dominantCount = frequencies.values.reduce((a, b) => a > b ? a : b);
    final hasStableGrid = dominantCount / rows.length >= 0.75;
    final isTextRich = populatedCells / totalCells >= 0.5;
    final isMediaHeavy = mediaCells / totalCells >= 0.5;
    return hasStableGrid && isTextRich && !isMediaHeavy;
  }

  static List<dom.Element> _elementsBelongingToTable(
    dom.Element table,
    String selector,
  ) {
    return table.querySelectorAll(selector).where((element) {
      dom.Element? ancestor = element.parent;
      while (ancestor != null && ancestor.localName != 'table') {
        ancestor = ancestor.parent;
      }
      return identical(ancestor, table);
    }).toList();
  }

  static void _unwrapElements(List<dom.Element> elements) {
    for (final el in elements) {
      final children = el.nodes.toList();
      for (final child in children) {
        el.parentNode?.insertBefore(child, el);
      }
      el.remove();
    }
  }

  /// 剔除邮件追踪像素（1×1 不可见图片）
  static void _removeTrackingPixels(dom.DocumentFragment fragment) {
    for (final img in fragment.querySelectorAll('img')) {
      final w = img.attributes['width'] ?? '';
      final h = img.attributes['height'] ?? '';
      if ((w == '1' && h == '1') || (w == '0' || h == '0')) {
        img.remove();
      }
    }
  }

  /// 剔除隐藏元素：style="display:none" / visibility:hidden / opacity:0
  static void _removeHiddenElements(dom.DocumentFragment fragment) {
    final toRemove = <dom.Element>[];
    for (final el in fragment.querySelectorAll('*')) {
      final style = el.attributes['style'] ?? '';
      if (style.isEmpty) continue;
      if (_isHiddenByInlineStyle(style)) {
        toRemove.add(el);
      }
    }
    for (final el in toRemove) {
      el.remove();
    }
  }

  static bool _isHiddenByInlineStyle(String style) {
    for (final declaration in style.split(';')) {
      final separator = declaration.indexOf(':');
      if (separator <= 0) continue;

      final property = declaration.substring(0, separator).trim().toLowerCase();
      var value = declaration.substring(separator + 1).trim().toLowerCase();
      value = value.replaceFirst(RegExp(r'\s*!important\s*$'), '').trim();

      if (property == 'display' && value == 'none') return true;
      if (property == 'visibility' && value == 'hidden') return true;
      if (property != 'opacity') continue;

      final opacity = double.tryParse(value);
      if (opacity != null && opacity == 0) return true;
    }
    return false;
  }

  /// 提取核心正文算法（类似 Readability）
  static dom.Element? getReadabilityContent(dom.Document document) {
    // 1. Remove unwanted elements
    final junk = document.querySelectorAll(
      'script, style, noscript, nav, header, footer, aside, form, button',
    );
    for (final el in junk) {
      el.remove();
    }
    for (final iframe in document.querySelectorAll('iframe')) {
      if (YouTubeEmbedInfo.tryParse(iframe.attributes['src']) == null) {
        iframe.remove();
      }
    }

    // 2. Score paragraphs
    final paragraphs = document.querySelectorAll(
      'p, blockquote, article, div > text',
    );
    final candidates = <dom.Element, double>{};

    for (final p in paragraphs) {
      final text = p.text.trim();
      if (text.length < 25) continue;

      double score = 1.0;
      score += text.length / 100.0;
      score += text.split(',').length;
      score += text.split('，').length;
      score += text.split('。').length;

      final parent = p.parent;
      final grandParent = parent?.parent;

      if (parent != null) {
        candidates[parent] = (candidates[parent] ?? 0.0) + score;
      }
      if (grandParent != null) {
        candidates[grandParent] =
            (candidates[grandParent] ?? 0.0) + (score / 2.0);
      }
    }

    // 3. Find top candidate
    dom.Element? topCandidate;
    double topScore = 0;

    candidates.forEach((el, score) {
      final className = (el.attributes['class'] ?? '').toLowerCase();
      final id = (el.attributes['id'] ?? '').toLowerCase();

      if (className.contains('comment') ||
          id.contains('comment') ||
          className.contains('sidebar') ||
          id.contains('sidebar') ||
          className.contains('menu') ||
          id.contains('menu')) {
        score *= 0.1;
      }

      if (score > topScore) {
        topScore = score;
        topCandidate = el;
      }
    });

    return topCandidate;
  }

  static final _urlRe = RegExp(
    r'https?:\/\/[a-zA-Z0-9\-._~:/?#\[\]@!$&*+,;=%]*[a-zA-Z0-9\-_~/#]',
    caseSensitive: false,
  );

  /// 遍历 DOM 树，将纯文本中的 URL 替换为 <a> 标签
  static void _autoLinkifyTextNodes(dom.Node node, {bool insideLink = false}) {
    if (node is dom.DocumentFragment) {
      for (int i = node.nodes.length - 1; i >= 0; i--) {
        _autoLinkifyTextNodes(node.nodes[i], insideLink: insideLink);
      }
    } else if (node is dom.Element) {
      final isLink = insideLink || node.localName == 'a';
      // 跳过不可见或无需替换的标签
      if (const {
        'pre',
        'code',
        'script',
        'style',
        'noscript',
      }.contains(node.localName)) {
        return;
      }
      // 倒序遍历，因为替换文本节点时会修改父节点的 children 列表
      for (int i = node.nodes.length - 1; i >= 0; i--) {
        _autoLinkifyTextNodes(node.nodes[i], insideLink: isLink);
      }
    } else if (node is dom.Text) {
      if (insideLink) return;

      final text = node.text;
      // 快速筛查，避免无谓的正则消耗
      if (!text.contains('http://') && !text.contains('https://')) return;

      final matches = _urlRe.allMatches(text).toList();
      if (matches.isEmpty) return;

      final buffer = StringBuffer();
      var cursor = 0;
      for (final match in matches) {
        if (match.start > cursor) {
          buffer.write(htmlEscape.convert(text.substring(cursor, match.start)));
        }

        final url = match.group(0)!;
        final escapedUrl = htmlEscape.convert(url);
        buffer.write('<a href="$escapedUrl">$escapedUrl</a>');
        cursor = match.end;
      }
      if (cursor < text.length) {
        buffer.write(htmlEscape.convert(text.substring(cursor)));
      }

      final parent = node.parentNode;
      if (parent != null) {
        final fragment = html_parser.parseFragment(buffer.toString());
        final index = parent.nodes.indexOf(node);
        if (index != -1) {
          node.remove();
          parent.nodes.insertAll(index, fragment.nodes);
        }
      }
    }
  }
}

final class _NormalizedHtmlCacheEntry {
  final String rawHtml;
  final String normalizedHtml;

  const _NormalizedHtmlCacheEntry(this.rawHtml, this.normalizedHtml);
}
