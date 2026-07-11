import 'package:html/parser.dart' show HtmlParser;

abstract final class HtmlEntityUtils {
  static final RegExp _entityPattern = RegExp(
    r'&(#(?:x[0-9a-fA-F]+|\d+)|[a-zA-Z][a-zA-Z0-9]+);',
  );

  static const Map<String, String> _namedEntities = {
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'nbsp': ' ',
    'ensp': ' ',
    'ndash': '\u2013',
    'mdash': '\u2014',
    'hellip': '\u2026',
    'lsquo': '\u2018',
    'rsquo': '\u2019',
    'ldquo': '\u201C',
    'rdquo': '\u201D',
    'copy': '\u00A9',
    'reg': '\u00AE',
    'trade': '\u2122',
  };
  static final Map<String, String> _decodedNamedEntityCache = {};

  static String decodeText(String value) {
    if (!value.contains('&')) return value;

    return value.replaceAllMapped(_entityPattern, (match) {
      final entity = match.group(1);
      if (entity == null || entity.isEmpty) return match.group(0)!;

      if (entity.startsWith('#x') || entity.startsWith('#X')) {
        final codePoint = int.tryParse(entity.substring(2), radix: 16);
        return _charForCodePoint(codePoint) ?? match.group(0)!;
      }

      if (entity.startsWith('#')) {
        final codePoint = int.tryParse(entity.substring(1));
        return _charForCodePoint(codePoint) ?? match.group(0)!;
      }

      final knownEntity = _namedEntities[entity];
      if (knownEntity != null) return knownEntity;

      return _decodedNamedEntityCache.putIfAbsent(entity, () {
        final source = match.group(0)!;
        final parser = HtmlParser(source);
        final decoded = parser.parseFragment().text;
        if (parser.errors.isNotEmpty || decoded == null) return source;
        return _normalizeWhitespaceEntity(decoded);
      });
    });
  }

  static String? decodeNullableText(String? value) {
    if (value == null) return null;
    return decodeText(value);
  }

  static String? _charForCodePoint(int? codePoint) {
    if (codePoint == null || codePoint <= 0 || codePoint > 0x10FFFF) {
      return null;
    }
    if (codePoint >= 0xD800 && codePoint <= 0xDFFF) return null;
    return String.fromCharCode(codePoint);
  }

  static String _normalizeWhitespaceEntity(String value) {
    return switch (value) {
      '\u00A0' || '\u2002' || '\u2003' || '\u2009' => ' ',
      _ => value,
    };
  }
}
