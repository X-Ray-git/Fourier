import 'package:html/dom.dart' as dom;

/// Narrow compatibility fixes for source HTML that depends on site CSS which
/// is not available in the article reader.
abstract final class ArticleContentCompatibility {
  static const String authorListTag = 'fourier-author-list';
  static const String authorTag = 'fourier-author';
  static const Set<String> _emptyWrapperTags = {'a', 'span', 'li', 'ul', 'ol'};

  static void apply(dom.DocumentFragment fragment, {String? sourceUrl}) {
    _normalizeHuggingFaceAuthorBylines(fragment);
    _removeHuggingFaceAvatars(fragment);

    final host = Uri.tryParse(sourceUrl?.trim() ?? '')?.host.toLowerCase();
    if (host == 'marktechpost.com' || host == 'www.marktechpost.com') {
      _removeMarkTechPostCodeControls(fragment);
      _replaceBrokenMarkTechPostExplainers(fragment, sourceUrl!);
    }
  }

  static void _removeMarkTechPostCodeControls(dom.DocumentFragment fragment) {
    final controls = fragment
        .querySelectorAll(
          '[id="dm-copy-raw-code"], [id="user-content-dm-copy-raw-code"]',
        )
        .toList();
    for (final control in controls) {
      final parent = control.parent;
      control.remove();
      _removeEmptyWrappers(parent);
    }
  }

  static void _replaceBrokenMarkTechPostExplainers(
    dom.DocumentFragment fragment,
    String sourceUrl,
  ) {
    final headings = fragment.querySelectorAll('h1, h2, h3').where((heading) {
      return heading.text.trim().toLowerCase() == 'interactive explainer';
    }).toList();

    for (final heading in headings) {
      final parent = heading.parentNode;
      if (parent == null) continue;
      final headingIndex = parent.nodes.indexOf(heading);
      if (headingIndex < 0) continue;
      final following = parent.nodes
          .skip(headingIndex + 1)
          .toList(growable: false);
      final hasInjectedDocument = following.any(
        (node) => node is dom.Element && node.localName == 'title',
      );
      if (!hasInjectedDocument) continue;

      for (final trailingNode in following) {
        trailingNode.remove();
      }
      final notice = dom.Element.tag('p')
        ..append(dom.Element.tag('em')..text = '交互内容仅在原文网页中可用。')
        ..append(dom.Text(' '))
        ..append(
          dom.Element.tag('a')
            ..attributes['href'] = sourceUrl
            ..text = '打开原文',
        );
      parent.append(notice);
    }
  }

  static void _normalizeHuggingFaceAuthorBylines(
    dom.DocumentFragment fragment,
  ) {
    final bylines = fragment
        .querySelectorAll('[data-target="BlogAuthorsByline"]')
        .toList();

    for (final byline in bylines) {
      final replacement = dom.Element.tag(authorListTag);
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

        final author = dom.Element.tag(authorTag)
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

      final alt = (image.attributes['alt'] ?? '').toLowerCase();
      final classes = (image.attributes['class'] ?? '').toLowerCase();
      final hasAvatarSemantics =
          alt.contains('avatar') || classes.contains('rounded-full');
      if (!hasAvatarSemantics) return false;

      final uri = Uri.tryParse(
        source.startsWith('//') ? 'https:$source' : source,
      );
      if (uri?.host.toLowerCase() == 'cdn-avatars.huggingface.co') {
        return true;
      }

      final path = uri?.path.toLowerCase() ?? source.toLowerCase();
      return path.startsWith('/avatars/');
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
