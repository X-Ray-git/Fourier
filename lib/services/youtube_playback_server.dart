import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';

abstract final class YouTubePlaybackServer {
  static const _assetRoot = 'assets/youtube_player';
  static const _maxProxyRequestBytes = 2 * 1024 * 1024;
  static const _browserUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/131.0.0.0 Safari/537.36';
  static const _allowedMethods = {'GET', 'HEAD', 'POST'};
  static const _requestHeadersToDrop = {
    'accept-encoding',
    'connection',
    'content-length',
    'cookie',
    'host',
    'origin',
    'referer',
    'transfer-encoding',
  };
  static const _responseHeadersToDrop = {
    'connection',
    'content-length',
    'set-cookie',
    'transfer-encoding',
  };

  static final HttpClient _client = HttpClient()..autoUncompress = false;
  static Future<_ServerState>? _starting;

  static Future<Uri> playerUri(String videoId) async {
    final normalizedVideoId = videoId.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{6,20}$').hasMatch(normalizedVideoId)) {
      throw ArgumentError.value(videoId, 'videoId', 'Invalid YouTube ID');
    }

    final state = await (_starting ??= _start());
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: state.server.port,
      pathSegments: [state.capability, 'index.html'],
      queryParameters: {'videoId': normalizedVideoId},
    );
  }

  static Future<_ServerState> _start() async {
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    final state = _ServerState(server, _newCapability());
    server.listen(
      (request) => _handleRequest(state, request),
      onError: (Object error, StackTrace stackTrace) {
        Zone.current.handleUncaughtError(error, stackTrace);
      },
      cancelOnError: false,
    );
    return state;
  }

  static String _newCapability() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static Future<void> _handleRequest(
    _ServerState state,
    HttpRequest request,
  ) async {
    try {
      final segments = request.uri.pathSegments;
      if (segments.length != 2 || segments.first != state.capability) {
        await _sendStatus(request.response, HttpStatus.notFound);
        return;
      }

      switch (segments.last) {
        case 'index.html':
          await _serveAsset(
            request,
            '$_assetRoot/index.html',
            ContentType.html,
          );
        case 'youtube_player.js':
          await _serveAsset(
            request,
            '$_assetRoot/youtube_player.js',
            ContentType('application', 'javascript', charset: 'utf-8'),
          );
        case 'youtube_player.css':
          await _serveAsset(
            request,
            '$_assetRoot/youtube_player.css',
            ContentType('text', 'css', charset: 'utf-8'),
          );
        case 'proxy':
          await _proxy(request);
        default:
          await _sendStatus(request.response, HttpStatus.notFound);
      }
    } catch (_) {
      try {
        await _sendStatus(request.response, HttpStatus.internalServerError);
      } catch (_) {
        // The client may already have disconnected from a streaming response.
      }
    }
  }

  static Future<void> _serveAsset(
    HttpRequest request,
    String assetPath,
    ContentType contentType,
  ) async {
    if (request.method != 'GET' && request.method != 'HEAD') {
      await _sendStatus(
        request.response,
        HttpStatus.methodNotAllowed,
        allow: 'GET, HEAD',
      );
      return;
    }

    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final response = request.response;
    response.headers
      ..contentType = contentType
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('X-Content-Type-Options', 'nosniff')
      ..set(
        'Content-Security-Policy',
        "default-src 'none'; "
            "script-src 'self' 'unsafe-eval' 'wasm-unsafe-eval' 'unsafe-inline'; "
            "style-src 'self' 'unsafe-inline'; "
            "img-src 'self' data: blob:; "
            "font-src 'none'; "
            "media-src 'self' data: blob:; "
            "connect-src 'self';",
      );
    response.contentLength = bytes.length;
    if (request.method == 'GET') response.add(bytes);
    await response.close();
  }

  static Future<void> _proxy(HttpRequest request) async {
    if (!_allowedMethods.contains(request.method)) {
      await _sendStatus(
        request.response,
        HttpStatus.methodNotAllowed,
        allow: _allowedMethods.join(', '),
      );
      return;
    }

    final rawTarget = request.uri.queryParameters['target'];
    final target = rawTarget == null ? null : Uri.tryParse(rawTarget);
    if (target == null || !isAllowedProxyTarget(target)) {
      await _sendStatus(request.response, HttpStatus.badRequest);
      return;
    }

    final body = request.method == 'POST'
        ? await _readBoundedBody(request)
        : const <int>[];
    if (body == null) {
      await _sendStatus(request.response, HttpStatus.requestEntityTooLarge);
      return;
    }
    await _forward(request, target, body, redirectsRemaining: 4);
  }

  static Future<List<int>?> _readBoundedBody(HttpRequest request) async {
    final body = <int>[];
    await for (final chunk in request) {
      if (body.length + chunk.length > _maxProxyRequestBytes) return null;
      body.addAll(chunk);
    }
    return body;
  }

  static Future<void> _forward(
    HttpRequest localRequest,
    Uri target,
    List<int> body, {
    required int redirectsRemaining,
  }) async {
    final upstream = await _client.openUrl(localRequest.method, target);
    upstream.followRedirects = false;
    localRequest.headers.forEach((name, values) {
      if (_requestHeadersToDrop.contains(name.toLowerCase())) return;
      for (final value in values) {
        upstream.headers.add(name, value);
      }
    });
    upstream.headers.set(HttpHeaders.userAgentHeader, _browserUserAgent);
    if (body.isNotEmpty) upstream.add(body);

    final upstreamResponse = await upstream.close();
    final redirectLocation = upstreamResponse.headers.value(
      HttpHeaders.locationHeader,
    );
    if (_isRedirect(upstreamResponse.statusCode) && redirectLocation != null) {
      if (redirectsRemaining <= 0) {
        await upstreamResponse.drain<void>();
        await _sendStatus(localRequest.response, HttpStatus.badGateway);
        return;
      }
      final redirectedTarget = target.resolve(redirectLocation);
      await upstreamResponse.drain<void>();
      if (!isAllowedProxyTarget(redirectedTarget)) {
        await _sendStatus(localRequest.response, HttpStatus.badGateway);
        return;
      }
      await _forward(
        localRequest,
        redirectedTarget,
        body,
        redirectsRemaining: redirectsRemaining - 1,
      );
      return;
    }

    final response = localRequest.response;
    response.statusCode = upstreamResponse.statusCode;
    upstreamResponse.headers.forEach((name, values) {
      if (_responseHeadersToDrop.contains(name.toLowerCase())) return;
      for (final value in values) {
        response.headers.add(name, value);
      }
    });
    response.headers
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('X-Content-Type-Options', 'nosniff');
    if (localRequest.method == 'HEAD') {
      await upstreamResponse.drain<void>();
      await response.close();
      return;
    }
    await upstreamResponse.pipe(response);
  }

  static bool isAllowedProxyTarget(Uri target) {
    if (target.scheme != 'https' ||
        target.userInfo.isNotEmpty ||
        (target.hasPort && target.port != 443)) {
      return false;
    }
    final host = target.host.toLowerCase();
    return _isHostOrSubdomain(host, 'youtube.com') ||
        host == 'youtubei.googleapis.com' ||
        host == 'uytfe.sandbox.google.com' ||
        host.endsWith('.sandbox.googleapis.com') ||
        _isHostOrSubdomain(host, 'googlevideo.com');
  }

  static bool _isHostOrSubdomain(String host, String domain) =>
      host == domain || host.endsWith('.$domain');

  static bool _isRedirect(int statusCode) =>
      statusCode == HttpStatus.movedPermanently ||
      statusCode == HttpStatus.found ||
      statusCode == HttpStatus.seeOther ||
      statusCode == HttpStatus.temporaryRedirect ||
      statusCode == HttpStatus.permanentRedirect;

  static Future<void> _sendStatus(
    HttpResponse response,
    int statusCode, {
    String? allow,
  }) async {
    response.statusCode = statusCode;
    if (allow != null) response.headers.set(HttpHeaders.allowHeader, allow);
    await response.close();
  }
}

final class _ServerState {
  const _ServerState(this.server, this.capability);

  final HttpServer server;
  final String capability;
}
