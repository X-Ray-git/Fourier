import 'package:flutter_test/flutter_test.dart';

import 'package:fourier/services/article_image_service.dart';

void main() {
  test('recognizes animations after Folo proxy URL normalization', () {
    for (final source in [
      'https://cdnfile.sspai.com/example.gif',
      'https://cdnfile.sspai.com/example.APNG',
      'https://cdnfile.sspai.com/image?format=gif',
      'https://cdnfile.sspai.com/image?wx_fmt=apng',
    ]) {
      final proxied = ArticleImageService.toProxiedUrl(source)!;
      expect(proxied, startsWith('https://img.folo.is?url='));
      expect(ArticleImageService.isLikelyAnimatedImage(source), isTrue);
      expect(ArticleImageService.isLikelyAnimatedImage(proxied), isTrue);
      expect(ArticleImageService.toProxiedUrl(proxied), proxied);
    }
  });

  test(
    'does not classify static proxy sources or unrelated URLs as animated',
    () {
      for (final url in [
        ArticleImageService.toProxiedUrl(
          'https://cdnfile.sspai.com/example.png?format=webp',
        )!,
        'https://img.folo.is',
        'https://img.folo.is?url=',
        'https://img.folo.is?url=not-a-url.gif',
        'https://img.folo.is?url=javascript:example.gif',
        'https://img.folo.is?url=%FF',
        'https://img.folo.is?url=%E0%A4',
        'https://img.folo.is.example.com?url=https%3A%2F%2Fexample.com%2Fa.gif',
        'https://img.folo.is/other?url=https%3A%2F%2Fexample.com%2Fa.gif',
        'https://example.com/article?url=https%3A%2F%2Fexample.com%2Fa.gif',
        'https://example.com/image.webp',
      ]) {
        expect(ArticleImageService.isLikelyAnimatedImage(url), isFalse);
      }
    },
  );

  test('unwraps the known Jintiankansha proxy for WeChat images', () {
    const url =
        'http://img2.jintiankansha.me/get?src='
        'http://mmbiz.qpic.cn/mmbiz_png/example/640?wx_fmt=png&from=appmsg';

    expect(
      ArticleImageService.normalizeImageUrl(url),
      'https://mmbiz.qpic.cn/mmbiz_png/example/640?wx_fmt=png',
    );
  });

  test('keeps the Jintiankansha proxy for an unrelated nested host', () {
    const url =
        'http://img2.jintiankansha.me/get?src='
        'http://images.example.com/example.png';

    expect(
      ArticleImageService.normalizeImageUrl(url),
      'https://img2.jintiankansha.me/get?src='
      'http://images.example.com/example.png',
    );
  });

  test('preserves an encoded nested WeChat query string', () {
    const url =
        'https://img2.jintiankansha.me/get?src='
        'https%3A%2F%2Fmmbiz.qpic.cn%2Fexample%2F640%3Ftoken%3Da%2Bb%26from%3Dappmsg';

    expect(
      ArticleImageService.normalizeImageUrl(url),
      'https://mmbiz.qpic.cn/example/640?token=a+b&from=appmsg',
    );
  });

  test('does not unwrap a similar path on another proxy host', () {
    const url =
        'http://images.example.com/get?src='
        'http://mmbiz.qpic.cn/mmbiz_png/example/640?wx_fmt=png';

    expect(
      ArticleImageService.normalizeImageUrl(url),
      'https://images.example.com/get?src='
      'http://mmbiz.qpic.cn/mmbiz_png/example/640?wx_fmt=png',
    );
  });

  test('recognizes direct SVG resources', () {
    expect(
      ArticleImageService.isSvg('https://cdn.example.com/diagram.svg'),
      isTrue,
    );
  });

  test('does not treat auto-formatted proxy output as SVG', () {
    const url =
        'https://substackcdn.com/image/fetch/'
        r'$s_!hash!,w_1456,c_limit,f_auto,q_auto:good/'
        'https%3A%2F%2Fcdn.example.com%2Fdiagram.svg';

    expect(ArticleImageService.isSvg(url), isFalse);
  });

  test('keeps transformed SVG without auto format on the SVG path', () {
    const url =
        'https://cdn.example.com/image/fetch/'
        'w_1456,c_limit/'
        'https%3A%2F%2Forigin.example.com%2Fdiagram.svg';

    expect(ArticleImageService.isSvg(url), isTrue);
  });
}
