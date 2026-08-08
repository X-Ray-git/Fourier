import 'dart:io';

import 'package:fourier/services/youtube_playback_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('YouTubePlaybackServer proxy allowlist', () {
    test('accepts required YouTube and GoogleVideo HTTPS hosts', () {
      const targets = [
        'https://www.youtube.com/youtubei/v1/player',
        'https://youtubei.googleapis.com/youtubei/v1/player',
        'https://uytfe.sandbox.google.com/player',
        'https://foo.sandbox.googleapis.com/player',
        'https://rr1---sn.example.googlevideo.com/videoplayback',
      ];

      for (final target in targets) {
        expect(
          YouTubePlaybackServer.isAllowedProxyTarget(Uri.parse(target)),
          isTrue,
          reason: target,
        );
      }
    });

    test('rejects non-HTTPS, credentials, ports, and lookalike hosts', () {
      const targets = [
        'http://www.youtube.com/youtubei/v1/player',
        'https://user@example.com/path',
        'https://www.youtube.com:444/youtubei/v1/player',
        'https://youtube.com.example.net/path',
        'https://notgooglevideo.com/path',
        'https://googlevideo.com.example.net/path',
      ];

      for (final target in targets) {
        expect(
          YouTubePlaybackServer.isAllowedProxyTarget(Uri.parse(target)),
          isFalse,
          reason: target,
        );
      }
    });
  });

  group('YouTubePlaybackServer local runtime', () {
    test('rejects invalid video IDs before starting the server', () async {
      await expectLater(
        YouTubePlaybackServer.playerUri('../not-a-video'),
        throwsArgumentError,
      );
    });

    test('builds a loopback player URI behind a capability path', () async {
      final uri = await YouTubePlaybackServer.playerUri('dQw4w9WgXcQ');
      expect(uri.scheme, 'http');
      expect(uri.host, InternetAddress.loopbackIPv4.address);
      expect(uri.pathSegments, hasLength(2));
      expect(uri.pathSegments.first.length, greaterThanOrEqualTo(40));
      expect(uri.pathSegments.last, 'index.html');
      expect(uri.queryParameters['videoId'], 'dQw4w9WgXcQ');
    });
  });
}
