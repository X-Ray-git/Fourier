import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/services/image_network_cache.dart';

void main() {
  late HttpServer server;
  final timers = <Timer>[];
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.done.catchError((Object _) {});
      switch (request.uri.path) {
        case '/headers':
          break;
        case '/idle':
          request.response.bufferOutput = false;
          request.response.add([1]);
          await request.response.flush();
        case '/trickle':
          request.response.bufferOutput = false;
          final timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
            request.response.add([1]);
            unawaited(request.response.flush().catchError((Object _) {}));
          });
          timers.add(timer);
        case '/slow':
          request.response.bufferOutput = false;
          for (var i = 0; i < 4; i++) {
            request.response.add([i]);
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 60));
          }
          await request.response.close();
        case '/missing':
          request.response.statusCode = 404;
          await request.response.close();
        default:
          request.response.headers.set('Content-Type', 'image/png');
          request.response.headers.set('Cache-Control', 'max-age=600');
          request.response.headers.set('ETag', 'image-v1');
          request.response.add([1, 2, 3]);
          await request.response.close();
      }
    });
  });
  tearDown(() async {
    for (final t in timers) {
      t.cancel();
    }
    timers.clear();
    await server.close(force: true);
  });
  String url(String path) => 'http://127.0.0.1:${server.port}$path';
  BoundedImageFileService service({Duration? total}) => BoundedImageFileService(
    headerTimeout: const Duration(milliseconds: 150),
    readTimeout: const Duration(milliseconds: 100),
    totalTimeout: total ?? const Duration(seconds: 2),
  );

  test(
    'header timeout does not prevent a subsequent successful request',
    () async {
      final s = service();
      await expectLater(
        s.get(url('/headers')),
        throwsA(isA<TimeoutException>()),
      );
      final response = await s.get(url('/ok'));
      expect(await response.content.expand((x) => x).toList(), [1, 2, 3]);
      expect(response.eTag, 'image-v1');
      expect(response.fileExtension, '.png');
    },
  );
  test(
    'stalled response body fails rather than waiting indefinitely',
    () async {
      final response = await service().get(url('/idle'));
      await expectLater(
        response.content.drain<void>(),
        throwsA(isA<TimeoutException>()),
      );
    },
  );
  test('total deadline terminates an endlessly trickling response', () async {
    final response = await service(total: const Duration(milliseconds: 250))
        .get(url('/trickle'));
    await expectLater(
      response.content.drain<void>().timeout(const Duration(seconds: 2)),
      throwsA(
        isA<TimeoutException>().having(
          (e) => e.duration,
          'deadline',
          const Duration(milliseconds: 250),
        ),
      ),
    );
  });
  test('one timeout does not cancel another progressing image', () async {
    final s = service();
    final hanging = expectLater(
      s.get(url('/headers')),
      throwsA(isA<TimeoutException>()),
    );
    final response = await s.get(url('/slow'));
    expect(await response.content.expand((x) => x).toList(), [0, 1, 2, 3]);
    await hanging;
  });
  test(
    'HTTP errors retain status for cache manager failure handling',
    () async {
      final response = await service().get(url('/missing'));
      expect(response.statusCode, 404);
    },
  );
}
