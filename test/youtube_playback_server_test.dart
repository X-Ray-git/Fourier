import 'dart:io';
import 'dart:typed_data';

import 'package:fourier/services/youtube_playback_server.dart';
import 'package:flutter_test/flutter_test.dart';

/// flutter_test's binding replaces every HttpClient with a 400-returning mock.
/// The loopback server tests need real sockets, so they run inside a zone
/// whose HttpOverrides produce genuine clients.
class _RealHttpOverrides extends HttpOverrides {
  // Deliberately overridden: flutter_test's binding mock must not be used.
  @override
  // ignore: unnecessary_overrides
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('YouTubePlaybackServer proxy allowlist', () {
    test('accepts required YouTube and GoogleVideo HTTPS hosts', () {
      const targets = [
        'https://www.youtube.com/youtubei/v1/player',
        'https://www.youtube.com/api/jnn/v1/GenerateIT',
        'https://www.youtube-nocookie.com/embed/JQ97GiDwPxc?html5=1',
        'https://youtubei.googleapis.com/youtubei/v1/player',
        'https://jnn-pa.googleapis.com/\$rpc/google.internal.waa.v1.Waa/GenerateIT',
        'https://www.google.com/js/th/interpreter.js',
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
        'https://www.youtube-nocookie.com/watch?v=JQ97GiDwPxc',
        'https://evil.youtube-nocookie.com/embed/JQ97GiDwPxc',
        'https://evil.jnn-pa.googleapis.com/path',
        'https://jnn-pa.googleapis.com.example.net/path',
        'https://www.google.com/search?q=not-an-interpreter',
        'https://evil.google.com/js/th/interpreter.js',
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
        YouTubePlaybackServer.embedSession('../not-a-video'),
        throwsArgumentError,
      );
    });
  });

  group('YouTubePlaybackServer embed session', () {
    test(
      'loads the real YouTube embed page with an injected runtime',
      () async {
        final session = await YouTubePlaybackServer.embedSession('dQw4w9WgXcQ');
        expect(session.pageUri.scheme, 'https');
        expect(session.pageUri.host, 'www.youtube-nocookie.com');
        expect(session.pageUri.pathSegments, ['embed', 'dQw4w9WgXcQ']);

        final script = session.injectionScript;
        expect(script, contains('globalThis.__FOURIER_EMBED__'));
        expect(script, contains('proxyBase:"https://127.0.0.1:'));
        expect(script, contains('videoId:"dQw4w9WgXcQ"'));
        expect(script, contains('diagnosticsEnabled:true'));
        expect(script, contains('FourierVideoPlayer'));
      },
    );

    test('serves CORS preflight for the loopback proxy', () async {
      final session = await YouTubePlaybackServer.embedSession('dQw4w9WgXcQ');
      final proxyBase = Uri.parse(
        '${RegExp(r'proxyBase:"([^"]+)"').firstMatch(session.injectionScript)!.group(1)!}/',
      );
      expect(proxyBase.scheme, 'https');
      expect(proxyBase.host, InternetAddress.loopbackIPv4.address);
      await HttpOverrides.runZoned(() async {
        final client = HttpClient()
          ..badCertificateCallback = (cert, host, port) =>
              host == InternetAddress.loopbackIPv4.address;
        try {
          final request = await client.openUrl(
            'OPTIONS',
            proxyBase.resolve('proxy?target=https%3A%2F%2Fwww.youtube.com%2F'),
          );
          request.headers.set('Origin', 'https://www.youtube-nocookie.com');
          request.headers.set('Access-Control-Request-Method', 'POST');
          request.headers.set('Access-Control-Request-Headers', 'content-type');
          final response = await request.close();
          expect(response.statusCode, HttpStatus.noContent);
          expect(response.headers.value('Access-Control-Allow-Origin'), '*');
          expect(
            response.headers.value('Access-Control-Allow-Methods'),
            contains('POST'),
          );
          expect(response.headers.value('Access-Control-Allow-Headers'), '*');
          await response.drain<void>();
        } finally {
          client.close(force: true);
        }
      }, createHttpClient: (_) => _RealHttpOverrides().createHttpClient(null));
    });

    test('rejects foreign loopback certificates', () async {
      await YouTubePlaybackServer.embedSession('dQw4w9WgXcQ');
      expect(
        YouTubePlaybackServer.isTrustedLoopbackCertificate(
          certificateDer: null,
          host: InternetAddress.loopbackIPv4.address,
        ),
        isFalse,
      );
      expect(
        YouTubePlaybackServer.isTrustedLoopbackCertificate(
          certificateDer: Uint8List.fromList(List.filled(64, 0)),
          host: InternetAddress.loopbackIPv4.address,
        ),
        isFalse,
      );
      expect(
        YouTubePlaybackServer.isTrustedLoopbackCertificate(
          certificateDer: Uint8List.fromList(List.filled(64, 0)),
          host: 'example.com',
        ),
        isFalse,
      );
    });
  });
}
