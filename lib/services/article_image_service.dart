import '../utils/security_utils.dart';

abstract final class ArticleImageService {
  static const String _proxyBase = 'https://img.folo.is';

  /// Folo 图片代理域名规则（参考 Folo img-proxy 逻辑）
  /// 仅对需要特定 Referer 才能访问的 CDN 走代理
  static final List<_ProxyRule> _proxyRules = [
    _ProxyRule(domainPattern: RegExp(r'^https://\w+\.sinaimg\.cn')),
    _ProxyRule(domainPattern: RegExp(r'^https://i\.pximg\.net')),
    _ProxyRule(domainPattern: RegExp(r'^https://cdnfile\.sspai\.com')),
    _ProxyRule(domainPattern: RegExp(r'^https://(?:\w|-)+\.cdninstagram\.com')),
    _ProxyRule(domainPattern: RegExp(r'^https://[\w-]+\.xhscdn\.com')),
    _ProxyRule(domainPattern: RegExp(r'^https://sp1\.piokok\.com')),
    _ProxyRule(domainPattern: RegExp(r'^https://[\w-]+\.qbitai\.com')),
  ];

  /// 默认请求头（不含 Referer，图片代理会按域名补正确的 Referer）
  static const Map<String, String> httpHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36',
    'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
  };

  static String? normalizeImageUrl(String? rawUrl) {
    if (rawUrl == null) return null;
    var normalized = rawUrl.trim();
    if (normalized.isEmpty) return null;

    if (normalized.startsWith('//')) {
      normalized = 'https:$normalized';
    }
    normalized = normalized.replaceAll(' ', '%20');

    var uri = SecurityUtils.parseHttpUrl(normalized);
    if (uri == null) return null;

    // 许多 RSS 源的图片链接返回 http，强制升级到 https 提升可达率。
    if (uri.scheme.toLowerCase() == 'http') {
      uri = uri.replace(scheme: 'https');
    }
    return uri.toString();
  }

  /// 对需要特定 Referer 的 CDN 图片，通过 Folo 图片代理加载
  static String? toProxiedUrl(String? rawUrl) {
    final normalized = normalizeImageUrl(rawUrl);
    if (normalized == null) return null;

    for (final rule in _proxyRules) {
      if (rule.domainPattern.hasMatch(normalized)) {
        final encoded = Uri.encodeComponent(normalized);
        return '$_proxyBase?url=$encoded&width=&height=';
      }
    }
    return normalized;
  }

  static bool isSvg(String imageUrl) {
    final path = Uri.tryParse(imageUrl)?.path.toLowerCase() ?? '';
    return path.endsWith('.svg');
  }
}

class _ProxyRule {
  final RegExp domainPattern;

  const _ProxyRule({required this.domainPattern});
}
