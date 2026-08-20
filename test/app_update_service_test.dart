import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/services/app_update_service.dart';

void main() {
  group('AppUpdateService.compareVersions', () {
    test('compares semantic version components numerically', () {
      expect(AppUpdateService.compareVersions('2.1.0', '2.0.9'), isPositive);
      expect(AppUpdateService.compareVersions('2.0.10', '2.0.9'), isPositive);
      expect(AppUpdateService.compareVersions('1.9.9', '2.0.0'), isNegative);
    });

    test('accepts a release tag prefix', () {
      expect(AppUpdateService.compareVersions('v2.0.0', '2.0.0'), 0);
    });

    test('rejects unsupported version formats', () {
      expect(
        () => AppUpdateService.compareVersions('2.0.0-beta.1', '2.0.0'),
        throwsFormatException,
      );
    });
  });

  group('AppUpdateService.parseAndroidReleaseData', () {
    test('selects the signed Android asset for the release version', () {
      final release = AppUpdateService.parseAndroidReleaseData({
        'tag_name': 'v2.1.0',
        'name': 'v2.1.0',
        'body': 'release notes',
        'published_at': '2026-08-18T12:00:00Z',
        'assets': [
          {
            'name': 'Fourier-macOS-arm64-v2.1.0.zip',
            'browser_download_url': 'https://example.test/macos.zip',
            'size': 20,
            'digest': 'sha256:${List.filled(64, 'a').join()}',
          },
          {
            'name': 'Fourier-android-v2.1.0.apk',
            'browser_download_url': 'https://example.test/android.apk',
            'size': 10,
            'digest': 'sha256:${List.filled(64, 'b').join()}',
          },
        ],
      });

      expect(release.version, '2.1.0');
      expect(release.asset.name, 'Fourier-android-v2.1.0.apk');
      expect(release.asset.sha256, List.filled(64, 'b').join());
    });

    test('rejects an asset without a GitHub digest', () {
      expect(
        () => AppUpdateService.parseAndroidReleaseData({
          'tag_name': 'v2.1.0',
          'assets': [
            {
              'name': 'Fourier-android-v2.1.0.apk',
              'browser_download_url': 'https://example.test/android.apk',
              'size': 10,
              'digest': null,
            },
          ],
        }),
        throwsFormatException,
      );
    });
  });
}
