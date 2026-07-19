import 'dart:isolate';
import 'dart:math' as math;

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../models/article.dart';
import '../utils/article_content_utils.dart';
import '../utils/html_chunk_parser.dart';

abstract final class ArticleMarkdownExportService {
  static String buildArticle({
    required ArticleModel article,
    required List<HtmlChunk> chunks,
  }) {
    return _ArticleMarkdownExporter(article: article, chunks: chunks).build();
  }

  static Future<String> buildBatch(List<ArticleModel> articles) {
    final snapshot = articles.toList(growable: false);
    return Isolate.run(() {
      return snapshot
          .map((article) {
            final rawHtml = article.content?.trim() ?? '';
            final chunks = rawHtml.isEmpty
                ? const <HtmlChunk>[]
                : HtmlChunkParser.parseSync(
                    ArticleContentUtils.normalizeHtml(rawHtml),
                  );
            return _ArticleMarkdownExporter(
              article: article,
              chunks: chunks,
              includeMissingBodyNotice: rawHtml.isEmpty,
            ).build();
          })
          .where((markdown) => markdown.trim().isNotEmpty)
          .join('\n\n---\n\n');
    });
  }
}

class _ArticleMarkdownExporter {
  const _ArticleMarkdownExporter({
    required this.article,
    required this.chunks,
    this.includeMissingBodyNotice = false,
  });

  final ArticleModel article;
  final List<HtmlChunk> chunks;
  final bool includeMissingBodyNotice;

  String build() {
    final blocks = <String>[];

    final title = article.title.trim();
    if (title.isNotEmpty) {
      blocks.add('# ${_escapeHeading(title)}');
    }

    final metadata = <String>[];
    final feedTitle = article.feedTitle.trim();
    if (feedTitle.isNotEmpty && feedTitle != '?') {
      metadata.add('来源：$feedTitle');
    }
    final author = article.author?.trim();
    if (author != null && author.isNotEmpty) {
      metadata.add('作者：$author');
    }
    final publishedAt = article.publishedAt.trim();
    if (publishedAt.isNotEmpty) {
      metadata.add('发布：$publishedAt');
    }
    final url = article.url.trim();
    if (url.isNotEmpty) {
      metadata.add('原文：$url');
    }
    if (metadata.isNotEmpty) {
      blocks.add(metadata.map((line) => '> $line').join('\n'));
    }

    final body = chunks
        .asMap()
        .entries
        .where(
          (entry) => entry.key != 0 || !_isDuplicateTitleHeading(entry.value),
        )
        .map((entry) => _chunkToMarkdown(entry.value))
        .where((block) => block.trim().isNotEmpty)
        .join('\n\n');
    if (body.trim().isNotEmpty) {
      blocks.add(body);
    } else if (includeMissingBodyNotice) {
      blocks.add('> 正文尚未缓存');
    }

    return _normalizeBlockSpacing(blocks.join('\n\n'));
  }

  String _chunkToMarkdown(HtmlChunk chunk) {
    return switch (chunk.type) {
      HtmlChunkType.heading => _headingToMarkdown(chunk),
      HtmlChunkType.paragraph ||
      HtmlChunkType.rawHtml => _htmlToMarkdown(chunk.content),
      HtmlChunkType.image => _imageToMarkdown(chunk),
      HtmlChunkType.codeBlock => _codeToMarkdown(chunk.content),
      HtmlChunkType.blockquote => _blockquoteToMarkdown(chunk.content),
      HtmlChunkType.table => _tableToMarkdown(chunk.content),
      HtmlChunkType.list => _listToMarkdown(chunk.content),
      HtmlChunkType.horizontalRule => '---',
      HtmlChunkType.iframeVideo => _iframeToMarkdown(chunk),
      HtmlChunkType.authorList =>
        chunk.authors
            .map(
              (author) => author.handle.isEmpty
                  ? author.name
                  : '${author.name} (@${author.handle})',
            )
            .join(', '),
    };
  }

  String _headingToMarkdown(HtmlChunk chunk) {
    final level = (chunk.headingLevel ?? 2).clamp(1, 6);
    final text = _htmlToMarkdown(chunk.content).replaceAll('\n', ' ').trim();
    if (text.isEmpty) return '';
    return '${'#' * level} ${_escapeHeading(text)}';
  }

  bool _isDuplicateTitleHeading(HtmlChunk chunk) {
    if (chunk.type != HtmlChunkType.heading) return false;
    final heading = _normalizeComparableText(_htmlToMarkdown(chunk.content));
    final title = _normalizeComparableText(article.title);
    return heading.isNotEmpty && heading == title;
  }

  String _imageToMarkdown(HtmlChunk chunk) {
    final url = (chunk.imageSrc ?? chunk.attributes['src'] ?? '').trim();
    if (url.isEmpty) return '';
    final alt = (chunk.imageAlt ?? chunk.attributes['alt'] ?? '').trim();
    return '![${_escapeBrackets(alt)}]($url)';
  }

  String _codeToMarkdown(String code) {
    final fence = code.contains('```') ? '````' : '```';
    return '$fence\n${code.trim()}\n$fence';
  }

  String _blockquoteToMarkdown(String html) {
    final text = _htmlToMarkdown(html);
    if (text.trim().isEmpty) return '';
    return text
        .split('\n')
        .map((line) => line.trim().isEmpty ? '>' : '> ${line.trim()}')
        .join('\n');
  }

  String _iframeToMarkdown(HtmlChunk chunk) {
    final src = (chunk.attributes['src'] ?? chunk.content).trim();
    return src;
  }

  String _listToMarkdown(String html) {
    final fragment = html_parser.parseFragment(html);
    final rootList =
        fragment.querySelector('ol') ?? fragment.querySelector('ul');
    final items = (rootList ?? fragment).children
        .where((element) => element.localName == 'li')
        .toList();
    if (items.isEmpty) return _htmlToMarkdown(html);

    final ordered = rootList?.localName == 'ol';
    return items
        .asMap()
        .entries
        .map((entry) {
          final marker = ordered ? '${entry.key + 1}. ' : '- ';
          final text = _nodesToMarkdown(entry.value.nodes).trim();
          return '$marker${text.replaceAll('\n', '\n  ')}';
        })
        .join('\n');
  }

  String _tableToMarkdown(String html) {
    final fragment = html_parser.parseFragment(html);
    final rows = fragment
        .querySelectorAll('tr')
        .map((row) {
          return row.children
              .where((cell) => cell.localName == 'th' || cell.localName == 'td')
              .map((cell) => _markdownTableCell(_nodesToMarkdown(cell.nodes)))
              .toList();
        })
        .where((row) => row.isNotEmpty)
        .toList();
    if (rows.isEmpty) return _htmlToMarkdown(html);

    final columnCount = rows
        .map((row) => row.length)
        .fold<int>(0, (max, length) => math.max(max, length));
    if (columnCount == 0) return '';

    List<String> pad(List<String> row) {
      return [...row, for (var i = row.length; i < columnCount; i++) ''];
    }

    final header = pad(rows.first);
    final bodyRows = rows.length > 1
        ? rows.skip(1).map(pad)
        : const Iterable<List<String>>.empty();
    final buffer = StringBuffer();
    buffer.writeln('| ${header.join(' | ')} |');
    buffer.writeln('| ${List.filled(columnCount, '---').join(' | ')} |');
    for (final row in bodyRows) {
      buffer.writeln('| ${row.join(' | ')} |');
    }
    return buffer.toString().trim();
  }

  String _htmlToMarkdown(String html) {
    final fragment = html_parser.parseFragment(html);
    return _normalizeInlineSpacing(_nodesToMarkdown(fragment.nodes));
  }

  String _nodesToMarkdown(List<html_dom.Node> nodes) {
    final buffer = StringBuffer();
    for (final node in nodes) {
      buffer.write(_nodeToMarkdown(node));
    }
    return buffer.toString();
  }

  String _nodeToMarkdown(html_dom.Node node) {
    if (node is html_dom.Text) return node.text;
    if (node is! html_dom.Element) return node.text ?? '';

    String childText() => _nodesToMarkdown(node.nodes);
    return switch (node.localName) {
      'br' => '\n',
      'p' || 'div' || 'section' || 'article' => '${childText().trim()}\n\n',
      'strong' || 'b' => _wrapInline('**', childText()),
      'em' || 'i' => _wrapInline('*', childText()),
      'code' => _inlineCode(node.text),
      'pre' => _codeToMarkdown(node.text),
      'blockquote' => _blockquoteToMarkdown(node.innerHtml),
      'a' => _linkToMarkdown(node),
      'img' => _imageElementToMarkdown(node),
      'ul' || 'ol' => _listToMarkdown(node.outerHtml),
      'table' => _tableToMarkdown(node.outerHtml),
      'hr' => '\n---\n',
      _ => childText(),
    };
  }

  String _linkToMarkdown(html_dom.Element element) {
    final text = _nodesToMarkdown(element.nodes).trim();
    final href = (element.attributes['href'] ?? '').trim();
    if (href.isEmpty) return text;
    if (text.isEmpty || text == href) return href;
    return '[${_escapeBrackets(text)}]($href)';
  }

  String _imageElementToMarkdown(html_dom.Element element) {
    final src = (element.attributes['src'] ?? '').trim();
    if (src.isEmpty) return '';
    final alt = (element.attributes['alt'] ?? '').trim();
    return '![${_escapeBrackets(alt)}]($src)';
  }

  String _wrapInline(String marker, String text) {
    final normalized = _normalizeInlineSpacing(text);
    return normalized.isEmpty ? '' : '$marker$normalized$marker';
  }

  String _inlineCode(String text) {
    final normalized = text.replaceAll('\n', ' ').trim();
    if (normalized.isEmpty) return '';
    final marker = normalized.contains('`') ? '``' : '`';
    return '$marker$normalized$marker';
  }

  String _markdownTableCell(String text) {
    return _normalizeInlineSpacing(
      text,
    ).replaceAll('\n', '<br>').replaceAll('|', r'\|');
  }

  String _normalizeInlineSpacing(String text) {
    return text
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'[ \t\r\f]+'), ' ')
        .replaceAll(RegExp(r' *\n *'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _normalizeBlockSpacing(String text) {
    return text
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _normalizeComparableText(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _escapeHeading(String text) {
    return text.replaceFirst(RegExp(r'^#+\s*'), '').trim();
  }

  String _escapeBrackets(String text) {
    return text.replaceAll('[', r'\[').replaceAll(']', r'\]');
  }
}
