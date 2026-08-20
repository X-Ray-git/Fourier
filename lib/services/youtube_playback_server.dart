import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class YouTubePlaybackServer {
  static const _assetRoot = 'assets/embed_video_player';
  static const _maxProxyRequestBytes = 2 * 1024 * 1024;
  static const _upstreamResponseTimeout = Duration(seconds: 20);
  static const _youtubeEmbedderUrl = 'https://github.com/X-Ray-git/Fourier/';
  static const _youtubeNoCookieOrigin = 'https://www.youtube-nocookie.com';
  static const _youtubeOrigin = 'https://www.youtube.com';
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

  static final HttpClient _client = HttpClient()
    ..autoUncompress = false
    ..connectionTimeout = const Duration(seconds: 12);
  static Future<_ServerState>? _starting;
  static Future<String>? _embedBundle;
  static _ServerState? _state;
  static _TlsMaterial? _tlsMaterial;

  /// 播放器 WebView 加载真实 YouTube embed 页面（真实 origin 与页面环境是
  /// BotGuard 签发真实 integrity token 的前提），并把运行时 bundle 与代理
  /// 地址注入该页面。所有 API/媒体请求仍走 loopback 代理。
  ///
  /// macOS 使用自签名 HTTPS loopback 代理：embed 页面是 https，浏览器会把
  /// 指向 http://127.0.0.1 的子资源当作混合内容拦截。证书在运行时生成，
  /// WebView 通过 SSL 认证回调仅对本站证书放行（见 `ShakaEmbedPlayer`）。
  static Future<YouTubeEmbedSession> embedSession(String videoId) async {
    final normalizedVideoId = videoId.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{6,20}$').hasMatch(normalizedVideoId)) {
      throw ArgumentError.value(videoId, 'videoId', 'Invalid YouTube ID');
    }

    final state = await (_starting ??= _start());
    final useTls = state.httpsServer != null;
    final proxyBase = Uri(
      scheme: useTls ? 'https' : 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: useTls ? state.httpsServer!.port : state.server.port,
      pathSegments: [state.capability],
    ).toString();
    final bundle = await (_embedBundle ??= _loadEmbedBundle());
    final config =
        'globalThis.__FOURIER_EMBED__ = '
        '{proxyBase:${jsonEncode(proxyBase)},'
        'videoId:${jsonEncode(normalizedVideoId)},'
        'diagnosticsEnabled:$kDebugMode};\n';
    return YouTubeEmbedSession(
      pageUri: Uri.parse(
        '$_youtubeNoCookieOrigin/embed/$normalizedVideoId'
        '?html5=1&playsinline=1',
      ),
      injectionScript: '$config$bundle',
    );
  }

  /// WebView SSL 认证回调的判定：只对当前进程生成、运行在本机 loopback
  /// 端口上的自签名证书放行，其余一律拒绝。
  static bool isTrustedLoopbackCertificate({
    Uint8List? certificateDer,
    String? host,
    int? port,
  }) {
    final state = _state;
    final httpsPort = state?.httpsServer?.port;
    if (httpsPort == null) return false;
    if (port != null && port != httpsPort) return false;
    if (host != null && host != InternetAddress.loopbackIPv4.address) {
      return false;
    }
    final expected = _tlsMaterial?.certDer;
    final actual = certificateDer;
    if (expected == null || actual == null) return false;
    if (expected.length != actual.length) return false;
    var diff = 0;
    for (var index = 0; index < expected.length; index++) {
      diff |= expected[index] ^ actual[index];
    }
    return diff == 0;
  }

  static Future<String> _loadEmbedBundle() async {
    final data = await rootBundle.load('$_assetRoot/embed_video_player.js');
    return utf8.decode(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }

  static Future<_ServerState> _start() async {
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    HttpServer? httpsServer;
    if (Platform.isMacOS) {
      try {
        final tls = await _ensureTlsMaterial();
        final context = SecurityContext();
        context.useCertificateChainBytes(utf8.encode(tls.certPem));
        context.usePrivateKeyBytes(utf8.encode(tls.keyPem));
        httpsServer = await HttpServer.bindSecure(
          InternetAddress.loopbackIPv4,
          0,
          context,
          shared: false,
        );
      } catch (error) {
        debugPrint(
          '[YouTubePlaybackServer] HTTPS loopback unavailable: $error',
        );
      }
    }
    final state = _ServerState(server, httpsServer, _newCapability());
    _state = state;
    server.listen(
      (request) => _handleRequest(state, request),
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('[YouTubePlaybackServer] local server error: $error');
      },
      cancelOnError: false,
    );
    httpsServer?.listen(
      (request) => _handleRequest(state, request),
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('[YouTubePlaybackServer] local TLS server error: $error');
      },
      cancelOnError: false,
    );
    return state;
  }

  /// 运行时生成只用于 127.0.0.1 loopback 的自签名证书（每进程一份，存于
  /// 系统临时目录）。openssl 不可用时降级为纯 HTTP 代理。
  static Future<_TlsMaterial> _ensureTlsMaterial() async {
    final existing = _tlsMaterial;
    if (existing != null) return existing;
    final dir = await Directory.systemTemp.createTemp('fourier_yt_tls_');
    final certPath = '${dir.path}/cert.pem';
    final keyPath = '${dir.path}/key.pem';
    try {
      final result = await Process.run('/usr/bin/openssl', [
        'req',
        '-x509',
        '-newkey',
        'rsa:2048',
        '-keyout',
        keyPath,
        '-out',
        certPath,
        '-days',
        '397',
        '-nodes',
        '-subj',
        '/CN=127.0.0.1',
        '-addext',
        'subjectAltName=IP:127.0.0.1,DNS:localhost',
      ]);
      if (result.exitCode != 0) {
        throw StateError('openssl cert generation failed: ${result.stderr}');
      }
      final certPem = await File(certPath).readAsString();
      final keyPem = await File(keyPath).readAsString();
      final material = _TlsMaterial(certPem, keyPem, _pemToDer(certPem));
      _tlsMaterial = material;
      return material;
    } finally {
      // SecurityContext 使用内存中的 PEM；证书与私钥不应残留在磁盘。
      try {
        await dir.delete(recursive: true);
      } catch (_) {
        // 系统临时目录清理失败不应阻断播放器启动。
      }
    }
  }

  static List<int> _pemToDer(String pem) {
    final base64 = pem
        .replaceAll(RegExp(r'-----(BEGIN|END) CERTIFICATE-----'), '')
        .replaceAll(RegExp(r'\s'), '');
    return base64Decode(base64);
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
      _applyCorsHeaders(request.response);
      if (request.method == 'OPTIONS') {
        if (kDebugMode) {
          final target = request.uri.queryParameters['target'];
          final host = target == null ? null : Uri.tryParse(target)?.host;
          debugPrint('[YouTubeProxy] preflight for ${host ?? 'unknown'}');
        }
        await _sendStatus(request.response, HttpStatus.noContent);
        return;
      }
      final segments = request.uri.pathSegments;
      if (segments.length != 2 || segments.first != state.capability) {
        await _sendStatus(request.response, HttpStatus.notFound);
        return;
      }

      switch (segments.last) {
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
    final method = localRequest.method;
    final host = target.host;
    final stopwatch = Stopwatch()..start();
    final resource = _proxyResource(target);
    final itag = target.queryParameters['itag'];
    final requestRange = _safeByteRange(
      localRequest.headers.value(HttpHeaders.rangeHeader),
    );
    try {
      final upstream = await _client.openUrl(method, target);
      upstream.followRedirects = false;
      localRequest.headers.forEach((name, values) {
        if (_requestHeadersToDrop.contains(name.toLowerCase())) return;
        for (final value in values) {
          upstream.headers.add(name, value);
        }
      });
      // Keep the WebView's real user agent. BotGuard fingerprints the actual
      // browser environment, so replacing it with a synthetic Chrome user
      // agent can make GenerateIT return only a fallback token.
      _applyYouTubeEmbedHeaders(upstream, target, body);
      if (body.isNotEmpty) upstream.add(body);

      final upstreamResponse = await upstream.close().timeout(
        _upstreamResponseTimeout,
      );
      final contentRange = _safeByteRange(
        upstreamResponse.headers.value(HttpHeaders.contentRangeHeader),
      );
      final redirectLocation = upstreamResponse.headers.value(
        HttpHeaders.locationHeader,
      );
      if (_isRedirect(upstreamResponse.statusCode) &&
          redirectLocation != null) {
        _debugProxyLog(
          'redirect',
          fields: {
            'method': method,
            'host': host,
            'resource': resource,
            'statusCode': upstreamResponse.statusCode,
            'headerMs': stopwatch.elapsedMilliseconds,
            'redirectsRemaining': redirectsRemaining,
          },
        );
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

      _debugProxyLog(
        'response',
        fields: {
          'method': method,
          'host': host,
          'resource': resource,
          'statusCode': upstreamResponse.statusCode,
          'headerMs': stopwatch.elapsedMilliseconds,
          if (_isHostOrSubdomain(host, 'googlevideo.com'))
            'hasPot': target.queryParameters.containsKey('pot'),
          if (itag != null && RegExp(r'^\d+$').hasMatch(itag)) 'itag': itag,
          if (localRequest.headers.value(HttpHeaders.rangeHeader) != null)
            'hasRange': true,
          'range': ?requestRange,
          'contentRange': ?contentRange,
          if (upstreamResponse.contentLength >= 0)
            'contentLength': upstreamResponse.contentLength,
          'redirectsRemaining': redirectsRemaining,
        },
      );
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
    } catch (e) {
      // 只记录安全诊断信息：目标 host、方法、重定向次数与错误类型，
      // 不记录完整签名 URL、Token 或请求体。
      _debugProxyLog(
        'error',
        fields: {
          'method': method,
          'host': host,
          'resource': resource,
          'elapsedMs': stopwatch.elapsedMilliseconds,
          'redirectsRemaining': redirectsRemaining,
          'errorType': e.runtimeType.toString(),
        },
      );
      rethrow;
    }
  }

  /// 本地代理的安全 debug 诊断日志（仅 debug 构建，不记录敏感内容）。
  static void _debugProxyLog(
    String event, {
    required Map<String, Object> fields,
  }) {
    if (!kDebugMode) return;
    final details = fields.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    debugPrint('[YouTubeProxy] $event $details');
  }

  static bool isAllowedProxyTarget(Uri target) {
    if (target.scheme != 'https' ||
        target.userInfo.isNotEmpty ||
        (target.hasPort && target.port != 443)) {
      return false;
    }
    final host = target.host.toLowerCase();
    return _isHostOrSubdomain(host, 'youtube.com') ||
        (host == 'www.youtube-nocookie.com' &&
            target.path.startsWith('/embed/')) ||
        host == 'youtubei.googleapis.com' ||
        host == 'jnn-pa.googleapis.com' ||
        (host == 'www.google.com' && target.path.startsWith('/js/th/')) ||
        host == 'uytfe.sandbox.google.com' ||
        host.endsWith('.sandbox.googleapis.com') ||
        _isHostOrSubdomain(host, 'googlevideo.com');
  }

  static String _proxyResource(Uri target) {
    final host = target.host.toLowerCase();
    if (_isHostOrSubdomain(host, 'googlevideo.com')) return 'media';
    if (target.path == '/youtubei/v1/player') return 'player-api';
    if (target.path == '/api/jnn/v1/GenerateIT' ||
        target.path == '/youtubei/v1/att/get') {
      return 'attestation';
    }
    if (host == 'www.youtube-nocookie.com' &&
        target.path.startsWith('/embed/')) {
      return 'embed-page';
    }
    return 'other';
  }

  static String? _safeByteRange(String? value) {
    if (value == null) return null;
    final normalized = value.trim().toLowerCase();
    return RegExp(r'^(bytes[ =])?\d+-\d+(\/\d+)?$').hasMatch(normalized)
        ? normalized
        : null;
  }

  static void _applyYouTubeEmbedHeaders(
    HttpClientRequest upstream,
    Uri target,
    List<int> body,
  ) {
    final host = target.host.toLowerCase();
    if (_isHostOrSubdomain(host, 'youtube.com') &&
        target.path == '/api/jnn/v1/GenerateIT') {
      upstream.headers
        ..set('Origin', _youtubeOrigin)
        ..set(HttpHeaders.refererHeader, '$_youtubeOrigin/');
      return;
    }
    if (host == 'www.youtube-nocookie.com' &&
        target.path.startsWith('/embed/')) {
      upstream.headers.set(HttpHeaders.refererHeader, _youtubeEmbedderUrl);
      return;
    }
    if (!_isHostOrSubdomain(host, 'youtube.com') ||
        target.path != '/youtubei/v1/player' ||
        body.isEmpty) {
      return;
    }

    try {
      final payload = jsonDecode(utf8.decode(body));
      if (payload is! Map) return;
      final context = payload['context'];
      final client = context is Map ? context['client'] : null;
      if (client is! Map || client['clientName'] != 'WEB_EMBEDDED_PLAYER') {
        return;
      }
      final videoId = payload['videoId'];
      if (videoId is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{6,20}$').hasMatch(videoId)) {
        return;
      }
      upstream.headers
        ..set('Origin', _youtubeNoCookieOrigin)
        ..set(
          HttpHeaders.refererHeader,
          '$_youtubeNoCookieOrigin/embed/$videoId',
        );
    } catch (_) {
      // Non-JSON requests follow the normal proxy path without synthesized
      // embedded-player identity headers.
    }
  }

  /// 真实 embed 页面与 loopback 代理不同源，代理响应必须放行 CORS。
  /// 运行时请求会带非安全头（user-agent、X-Origin、X-Goog-Visitor-Id、
  /// x-goog-api-key 等），预检按通配放行全部请求头；无凭据请求模式下
  /// `Access-Control-Allow-Headers: *` 是合法的。
  static void _applyCorsHeaders(HttpResponse response) {
    response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, HEAD, POST, OPTIONS')
      ..set('Access-Control-Allow-Headers', '*')
      ..set('Access-Control-Max-Age', '7200');
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
  const _ServerState(this.server, this.httpsServer, this.capability);

  final HttpServer server;
  final HttpServer? httpsServer;
  final String capability;
}

final class _TlsMaterial {
  const _TlsMaterial(this.certPem, this.keyPem, this.certDer);

  final String certPem;
  final String keyPem;
  final List<int> certDer;
}

/// 真实 YouTube embed 页面的播放会话：WebView 加载 [pageUri]，随后把
/// [injectionScript]（运行时配置 + 播放器 bundle）注入该页面。
final class YouTubeEmbedSession {
  const YouTubeEmbedSession({
    required this.pageUri,
    required this.injectionScript,
  });

  final Uri pageUri;
  final String injectionScript;
}
