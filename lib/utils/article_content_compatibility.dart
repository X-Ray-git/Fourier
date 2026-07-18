import 'package:html/dom.dart' as dom;

/// Narrow compatibility fixes for source HTML that depends on site CSS which
/// is not available in the article reader.
abstract final class ArticleContentCompatibility {
  static const Set<String> _emptyWrapperTags = {'a', 'span', 'li', 'ul', 'ol'};

  static void apply(dom.DocumentFragment fragment) {
    _normalizeHuggingFaceAuthorBylines(fragment);
    _removeHuggingFaceAvatars(fragment);
  }

  static void _normalizeHuggingFaceAuthorBylines(
    dom.DocumentFragment fragment,
  ) {
    final bylines = fragment
        .querySelectorAll('[data-target="BlogAuthorsByline"]')
        .toList();

    for (final byline in bylines) {
      final replacement = dom.Element.tag('auto-folo-author-list');
      final seen = <String>{};

      for (final image in byline.querySelectorAll('img')) {
        final classes = (image.attributes['class'] ?? '').toLowerCase();
        final alt = (image.attributes['alt'] ?? '').trim();
        if (!classes.contains('rounded-full') ||
            !alt.toLowerCase().contains('avatar')) {
          continue;
        }

        final avatarUrl = _absoluteHuggingFaceUrl(_imageSource(image));
        if (avatarUrl.isEmpty) continue;

        final name = alt
            .replaceFirst(RegExp(r"['’]s avatar$", caseSensitive: false), '')
            .replaceFirst(RegExp(r' avatar$', caseSensitive: false), '')
            .trim();
        if (name.isEmpty) continue;

        final link = image.parent?.localName == 'a' ? image.parent : null;
        final profileUrl = _absoluteHuggingFaceUrl(
          link?.attributes['href'] ?? '',
        );
        final handle = _profileHandle(link?.attributes['href'] ?? '');
        final identity = '$name\u0000$avatarUrl';
        if (!seen.add(identity)) continue;

        final author = dom.Element.tag('auto-folo-author')
          ..attributes['name'] = name
          ..attributes['avatar'] = avatarUrl;
        if (handle.isNotEmpty) author.attributes['handle'] = handle;
        if (profileUrl.isNotEmpty) {
          author.attributes['profile'] = profileUrl;
        }
        replacement.append(author);
      }

      if (replacement.children.isEmpty) continue;
      byline.parentNode?.insertBefore(replacement, byline);
      byline.remove();
    }
  }

  static void _removeHuggingFaceAvatars(dom.DocumentFragment fragment) {
    final avatars = fragment.querySelectorAll('img').where((image) {
      final source = _imageSource(image);
      if (source.isEmpty) return false;

      final uri = Uri.tryParse(
        source.startsWith('//') ? 'https:$source' : source,
      );
      if (uri?.host.toLowerCase() == 'cdn-avatars.huggingface.co') {
        return true;
      }

      final path = uri?.path.toLowerCase() ?? source.toLowerCase();
      if (!path.startsWith('/avatars/')) return false;

      final alt = (image.attributes['alt'] ?? '').toLowerCase();
      final classes = (image.attributes['class'] ?? '').toLowerCase();
      return alt.contains('avatar') || classes.contains('rounded-full');
    }).toList();

    for (final avatar in avatars) {
      final parent = avatar.parent;
      avatar.remove();
      _removeEmptyWrappers(parent);
    }
  }

  static String _imageSource(dom.Element image) {
    return (image.attributes['src'] ??
            image.attributes['data-src'] ??
            image.attributes['data-original'] ??
            image.attributes['data-lazy-src'] ??
            '')
        .trim();
  }

  static String _absoluteHuggingFaceUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    if (value.startsWith('//')) return 'https:$value';
    if (value.startsWith('/')) return 'https://huggingface.co$value';
    final uri = Uri.tryParse(value);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return '';
    }
    return value;
  }

  static String _profileHandle(String raw) {
    final path = Uri.tryParse(raw.trim())?.path ?? '';
    final segments = path.split('/').where((segment) => segment.isNotEmpty);
    if (segments.isEmpty) return '';
    try {
      return Uri.decodeComponent(segments.first);
    } on FormatException {
      return segments.first;
    }
  }

  static void _removeEmptyWrappers(dom.Element? element) {
    var current = element;
    while (current != null && _emptyWrapperTags.contains(current.localName)) {
      if (current.text.trim().isNotEmpty ||
          current.querySelector('img, video, iframe, table, pre, code') !=
              null) {
        return;
      }
      final parent = current.parent;
      current.remove();
      current = parent;
    }
  }
}
