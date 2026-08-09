import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/utils/image_clipboard.dart';

void main() {
  late HttpServer server;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      switch (request.uri.path) {
        case '/small':
          request.response.contentLength = 4;
          request.response.add([1, 2, 3, 4]);
        case '/declared-large':
          request.response.contentLength = 6;
          request.response.add([1, 2, 3, 4, 5, 6]);
        case '/chunked-large':
          request.response.contentLength = -1;
          request.response.add([1, 2, 3]);
          request.response.add([4, 5, 6]);
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  String url(String path) => 'http://127.0.0.1:${server.port}$path';

  test('downloads a response within the byte limit', () async {
    final bytes = await ImageClipboard.downloadBytes(
      url('/small'),
      maxBytes: 4,
    );

    expect(bytes, [1, 2, 3, 4]);
  });

  test('rejects a declared response larger than the byte limit', () async {
    final bytes = await ImageClipboard.downloadBytes(
      url('/declared-large'),
      maxBytes: 4,
    );

    expect(bytes, isNull);
  });

  test('stops a chunked response after it exceeds the byte limit', () async {
    final bytes = await ImageClipboard.downloadBytes(
      url('/chunked-large'),
      maxBytes: 4,
    );

    expect(bytes, isNull);
  });
}
