import 'package:html/dom.dart' as dom;

/// Normalizes CoderBill's Circle/SendGrid email templates into reader content.
///
/// The source check and the template check are both required so these rules do
/// not leak into ordinary inbox messages or regular articles.
abstract final class CoderBillEmailCompatibility {
  static const _feedId = 'coderbill';
  static const _circleRedirectHost = 'email.notification.circle.so';
  static const _sendGridAssetHost = 'cdn.mcauto-images-production.sendgrid.net';

  static bool appliesTo(
    dom.DocumentFragment fragment, {
    String? feedId,
    String? category,
  }) {
    if (feedId?.trim().toLowerCase() != _feedId ||
        category?.trim().toLowerCase() != 'inbox') {
      return false;
    }

    if (fragment.querySelector(
          '#user-content-bodyTable, #user-content-emailBody',
        ) !=
        null) {
      return true;
    }

    return fragment.querySelectorAll('a[href]').any((link) {
      final uri = Uri.tryParse(link.attributes['href']?.trim() ?? '');
      return uri?.host.toLowerCase() == _circleRedirectHost;
    });
  }

  static void apply(dom.DocumentFragment fragment) {
    _removeFooter(fragment);
    _removeCircleAppPromotion(fragment);
    _normalizeCallToActionLinks(fragment);
    _stripEmailPresentation(fragment);
  }

  static void _removeFooter(dom.DocumentFragment fragment) {
    const footerLabels = {
      'change notification settings',
      'unsubscribe from all emails',
    };
    final footerLinks = fragment.querySelectorAll('a').where((link) {
      return footerLabels.contains(_normalizedText(link));
    }).toList();
    if (footerLinks.isEmpty) return;

    final candidates =
        fragment.querySelectorAll('table').where((table) {
            final text = table.text.toLowerCase();
            return footerLabels.any(text.contains);
          }).toList()
          ..sort((a, b) => a.outerHtml.length.compareTo(b.outerHtml.length));

    if (candidates.isNotEmpty) {
      candidates.first.remove();
      return;
    }
    for (final link in footerLinks) {
      link.remove();
    }
  }

  static void _removeCircleAppPromotion(dom.DocumentFragment fragment) {
    for (final element in fragment.querySelectorAll('h1, h2, h3, h4, p')) {
      if (_normalizedText(element) == 'get the circle app') {
        element.remove();
      }
    }

    final badges = fragment.querySelectorAll('img').where((image) {
      final source = (image.attributes['src'] ?? '').trim();
      final uri = Uri.tryParse(source);
      if (uri?.host.toLowerCase() != _sendGridAssetHost) return false;

      final dimensions =
          '${image.attributes['width'] ?? ''} '
                  '${image.attributes['height'] ?? ''} '
                  '${image.attributes['style'] ?? ''} $source'
              .toLowerCase();
      return dimensions.contains('140') ||
          dimensions.contains('153') ||
          dimensions.contains('498x167');
    }).toList();

    for (final badge in badges) {
      final parentLink = badge.parent?.localName == 'a' ? badge.parent : null;
      badge.remove();
      if (parentLink != null && parentLink.text.trim().isEmpty) {
        parentLink.remove();
      }
    }
  }

  static void _normalizeCallToActionLinks(dom.DocumentFragment fragment) {
    for (final link in fragment.querySelectorAll('a')) {
      final text = _normalizedText(link);
      if (text == 'view post') {
        link.attributes['data-fourier-email-action'] = 'primary';
      }
    }
  }

  static void _stripEmailPresentation(dom.DocumentFragment fragment) {
    const removableAttributes = {
      'align',
      'bgcolor',
      'border',
      'cellpadding',
      'cellspacing',
      'class',
      'height',
      'id',
      'role',
      'style',
      'valign',
      'width',
    };

    for (final element in fragment.querySelectorAll('*')) {
      final tag = element.localName;
      if (tag == 'table' || tag == 'tr' || tag == 'td' || tag == 'th') {
        continue;
      }
      if (element.localName == 'img') {
        _preserveImageDimensions(element);
        element.attributes.remove('class');
        element.attributes.remove('id');
        element.attributes.remove('style');
        continue;
      }
      for (final attribute in removableAttributes) {
        element.attributes.remove(attribute);
      }
    }
  }

  static void _preserveImageDimensions(dom.Element image) {
    final style = image.attributes['style'] ?? '';
    for (final property in const ['width', 'height']) {
      if (image.attributes[property]?.trim().isNotEmpty ?? false) continue;
      final match = RegExp(
        '(?:^|;)\\s*$property\\s*:\\s*(\\d+(?:\\.\\d+)?)px(?:\\s*!important)?(?:;|\$)',
        caseSensitive: false,
      ).firstMatch(style);
      final value = match?.group(1);
      if (value != null) image.attributes[property] = value;
    }
  }

  static String _normalizedText(dom.Element element) {
    return element.text.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
  }
}
