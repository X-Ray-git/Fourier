import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/services/external_link_service.dart';

void main() {
  group('ExternalLinkService 外链校验', () {
    test('空 URL 或非 http/https 返回 invalidUrl，不触发平台调用', () async {
      for (final raw in <String?>[
        null,
        '',
        '   ',
        'javascript:alert(1)',
        'tel:123',
        'ftp://x',
      ]) {
        final result = await ExternalLinkService.openUrl(raw);
        expect(result.opened, isFalse, reason: 'raw=$raw');
        expect(result.failure, ExternalLinkFailureType.invalidUrl);
      }
    });

    test('合法 http/https URL 进入 launchUrl 路径', () async {
      // 合法 URL 校验通过后才会走到平台 launch；这里只验证校验层放行。
      final result = await ExternalLinkService.openUrl('https://example.com/a');
      // 平台层（无真实浏览器环境）会返回失败，但不应是 invalidUrl。
      expect(result.failure, isNot(ExternalLinkFailureType.invalidUrl));
    });
  });
}
