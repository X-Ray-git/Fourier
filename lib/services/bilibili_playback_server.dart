import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/bilibili_embed_utils.dart';

abstract final class BilibiliPlaybackServer {
  static const _assetRoot = 'assets/embed_video_player';
  static const _maxApiResponseBytes = 12 * 1024 * 1024;
  static const _maxDanmakuResponseBytes = 8 * 1024 * 1024;
  static const _resolveTimeout = Duration(seconds: 20);
  static const _subtitleTimeout = Duration(seconds: 4);
  static const _upstreamResponseTimeout = Duration(seconds: 20);
  static const _browserUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/131.0.0.0 Safari/537.36';
  static const _sessionLifetime = Duration(hours: 1);
  static const _maxSessions = 32;
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

  static final HttpClient _apiClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12);
  static final HttpClient _mediaClient = HttpClient()
    ..autoUncompress = false
    ..connectionTimeout = const Duration(seconds: 12);
  static Future<_ServerState>? _starting;

  static Future<Uri> playerUri(BilibiliEmbedInfo info) async {
    final session = await _resolveSession(info).timeout(_resolveTimeout);
    final state = await (_starting ??= _start());
    _pruneSessions(state);
    final sessionId = _newCapability(18);
    state.sessions[sessionId] = session;
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: state.server.port,
      pathSegments: [state.capability, 'index.html'],
      queryParameters: {'provider': 'bilibili', 'session': sessionId},
    );
  }

  static Future<_ServerState> _start() async {
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    final state = _ServerState(server, _newCapability(32));
    server.listen(
      (request) => _handleRequest(state, request),
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('[BilibiliPlaybackServer] local server error: $error');
      },
      cancelOnError: false,
    );
    return state;
  }

  static void _pruneSessions(_ServerState state) {
    final cutoff = DateTime.now().subtract(_sessionLifetime);
    state.sessions.removeWhere(
      (_, session) => session.createdAt.isBefore(cutoff),
    );
    while (state.sessions.length >= _maxSessions) {
      state.sessions.remove(state.sessions.keys.first);
    }
  }

  static String _newCapability(int byteCount) {
    final random = Random.secure();
    final bytes = List<int>.generate(byteCount, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static Future<void> _handleRequest(
    _ServerState state,
    HttpRequest request,
  ) async {
    try {
      final segments = request.uri.pathSegments;
      if (segments.isEmpty || segments.first != state.capability) {
        await _sendStatus(request.response, HttpStatus.notFound);
        return;
      }

      if (segments.length == 2) {
        switch (segments[1]) {
          case 'index.html':
            await _serveAsset(
              request,
              '$_assetRoot/index.html',
              ContentType.html,
            );
          case 'embed_video_player.js':
            await _serveAsset(
              request,
              '$_assetRoot/embed_video_player.js',
              ContentType('application', 'javascript', charset: 'utf-8'),
            );
          case 'embed_video_player.css':
            await _serveAsset(
              request,
              '$_assetRoot/embed_video_player.css',
              ContentType('text', 'css', charset: 'utf-8'),
            );
          default:
            await _sendStatus(request.response, HttpStatus.notFound);
        }
        return;
      }

      if (segments.length < 4 || segments[1] != 'bilibili') {
        await _sendStatus(request.response, HttpStatus.notFound);
        return;
      }
      final session = state.sessions[segments[3]];
      if (session == null) {
        await _sendStatus(request.response, HttpStatus.notFound);
        return;
      }

      switch (segments[2]) {
        case 'bootstrap':
          await _serveBootstrap(state, request, session, segments[3]);
        case 'manifest':
          await _serveManifest(state, request, session, segments[3]);
        case 'media':
          await _proxyMedia(request, session);
        case 'subtitle':
          if (segments.length != 5) {
            await _sendStatus(request.response, HttpStatus.notFound);
            return;
          }
          await _serveSubtitle(request, session, segments[4]);
        case 'danmaku':
          if (segments.length != 5) {
            await _sendStatus(request.response, HttpStatus.notFound);
            return;
          }
          await _serveDanmaku(request, session, segments[4]);
        default:
          await _sendStatus(request.response, HttpStatus.notFound);
      }
    } catch (_) {
      try {
        await _sendStatus(request.response, HttpStatus.internalServerError);
      } catch (_) {
        // The client may have disconnected during a streaming response.
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

  static Future<void> _serveBootstrap(
    _ServerState state,
    HttpRequest request,
    _PlaybackSession session,
    String sessionId,
  ) async {
    if (request.method != 'GET') {
      await _sendStatus(
        request.response,
        HttpStatus.methodNotAllowed,
        allow: 'GET',
      );
      return;
    }
    final base = _localBaseUri(state);
    final body = jsonEncode({
      'title': session.title,
      'danmakuBaseUrl':
          '${base.replace(pathSegments: [state.capability, 'bilibili', 'danmaku', sessionId])}/',
      'manifestUrl': base
          .replace(
            pathSegments: [state.capability, 'bilibili', 'manifest', sessionId],
          )
          .toString(),
      'subtitles': [
        for (var index = 0; index < session.subtitles.length; index++)
          {
            'url': base
                .replace(
                  pathSegments: [
                    state.capability,
                    'bilibili',
                    'subtitle',
                    sessionId,
                    '$index.vtt',
                  ],
                )
                .toString(),
            'language': session.subtitles[index].language,
            'label': session.subtitles[index].label,
          },
      ],
    });
    await _sendText(
      request.response,
      body,
      ContentType('application', 'json', charset: 'utf-8'),
    );
  }

  static Future<void> _serveManifest(
    _ServerState state,
    HttpRequest request,
    _PlaybackSession session,
    String sessionId,
  ) async {
    if (request.method != 'GET' && request.method != 'HEAD') {
      await _sendStatus(
        request.response,
        HttpStatus.methodNotAllowed,
        allow: 'GET, HEAD',
      );
      return;
    }
    final base = _localBaseUri(state);
    final manifest = session.buildManifest((target) {
      return base.replace(
        pathSegments: [state.capability, 'bilibili', 'media', sessionId],
        queryParameters: {'target': target.toString()},
      );
    });
    if (request.method == 'HEAD') {
      request.response.headers.contentType = ContentType(
        'application',
        'dash+xml',
        charset: 'utf-8',
      );
      await request.response.close();
      return;
    }
    await _sendText(
      request.response,
      manifest,
      ContentType('application', 'dash+xml', charset: 'utf-8'),
    );
  }

  static Future<void> _serveSubtitle(
    HttpRequest request,
    _PlaybackSession session,
    String rawIndex,
  ) async {
    if (request.method != 'GET') {
      await _sendStatus(
        request.response,
        HttpStatus.methodNotAllowed,
        allow: 'GET',
      );
      return;
    }
    final index = int.tryParse(rawIndex.replaceAll('.vtt', ''));
    if (index == null || index < 0 || index >= session.subtitles.length) {
      await _sendStatus(request.response, HttpStatus.notFound);
      return;
    }
    await _sendText(
      request.response,
      session.subtitles[index].vtt,
      ContentType('text', 'vtt', charset: 'utf-8'),
    );
  }

  static Future<void> _serveDanmaku(
    HttpRequest request,
    _PlaybackSession session,
    String rawSegment,
  ) async {
    if (request.method != 'GET') {
      await _sendStatus(
        request.response,
        HttpStatus.methodNotAllowed,
        allow: 'GET',
      );
      return;
    }
    final segment = int.tryParse(rawSegment);
    final maxSegment = (session.duration / (6 * 60)).ceil();
    if (segment == null || segment < 1 || segment > maxSegment) {
      await _sendStatus(request.response, HttpStatus.notFound);
      return;
    }

    final target = danmakuSegmentUri(session.cid, segment);
    final requestToBilibili = await _apiClient.getUrl(target);
    requestToBilibili.headers
      ..set(HttpHeaders.userAgentHeader, _browserUserAgent)
      ..set(HttpHeaders.refererHeader, session.referer)
      ..set(HttpHeaders.acceptHeader, 'application/octet-stream');
    final upstream = await requestToBilibili.close();
    if (upstream.statusCode != HttpStatus.ok) {
      await upstream.drain<void>();
      await _sendStatus(request.response, HttpStatus.badGateway);
      return;
    }

    final bytes = BytesBuilder(copy: false);
    var byteCount = 0;
    await for (final chunk in upstream) {
      byteCount += chunk.length;
      if (byteCount > _maxDanmakuResponseBytes) {
        throw const FormatException('Bilibili danmaku segment is too large');
      }
      bytes.add(chunk);
    }
    final data = bytes.takeBytes();
    final response = request.response;
    response.headers
      ..contentType = ContentType.binary
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('X-Content-Type-Options', 'nosniff');
    response.contentLength = data.length;
    response.add(data);
    await response.close();
  }

  static Uri _localBaseUri(_ServerState state) => Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: state.server.port,
  );

  static Future<void> _proxyMedia(
    HttpRequest request,
    _PlaybackSession session,
  ) async {
    if (request.method != 'GET' && request.method != 'HEAD') {
      await _sendStatus(
        request.response,
        HttpStatus.methodNotAllowed,
        allow: 'GET, HEAD',
      );
      return;
    }
    final rawTarget = request.uri.queryParameters['target'];
    final target = rawTarget == null ? null : Uri.tryParse(rawTarget);
    if (target == null ||
        !session.allowedMediaUrls.contains(target.toString())) {
      await _sendStatus(request.response, HttpStatus.badRequest);
      return;
    }
    await _forwardMedia(
      request,
      target,
      session.referer,
      redirectsRemaining: 4,
    );
  }

  static Future<void> _forwardMedia(
    HttpRequest localRequest,
    Uri target,
    String referer, {
    required int redirectsRemaining,
  }) async {
    final upstream = await _mediaClient.openUrl(localRequest.method, target);
    upstream.followRedirects = false;
    localRequest.headers.forEach((name, values) {
      if (_requestHeadersToDrop.contains(name.toLowerCase())) return;
      for (final value in values) {
        upstream.headers.add(name, value);
      }
    });
    upstream.headers
      ..set(HttpHeaders.userAgentHeader, _browserUserAgent)
      ..set(HttpHeaders.refererHeader, referer)
      ..set('Origin', 'https://www.bilibili.com');

    final upstreamResponse = await upstream.close().timeout(
      _upstreamResponseTimeout,
    );
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
      if (!isAllowedMediaTarget(redirectedTarget)) {
        await _sendStatus(localRequest.response, HttpStatus.badGateway);
        return;
      }
      await _forwardMedia(
        localRequest,
        redirectedTarget,
        referer,
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

  static bool isAllowedMediaTarget(Uri target) {
    if (target.scheme != 'https' ||
        target.userInfo.isNotEmpty ||
        (target.hasPort && target.port != 443)) {
      return false;
    }
    final host = target.host.toLowerCase();
    return _isHostOrSubdomain(host, 'bilivideo.com') ||
        host == 'upos-hz-mirrorakam.akamaized.net';
  }

  static Future<_PlaybackSession> _resolveSession(
    BilibiliEmbedInfo info,
  ) async {
    final referer = info.externalUri.toString();
    var cid = info.cid;
    var title = 'Bilibili';
    if (cid == null) {
      final viewUri = Uri.https(
        'api.bilibili.com',
        '/x/web-interface/view',
        info.bvid != null ? {'bvid': info.bvid!} : {'aid': '${info.aid}'},
      );
      final response = await _getApiJson(viewUri, referer);
      final data = _apiData(response);
      cid = selectCid(data, info.page);
      final rawTitle = data['title'];
      if (rawTitle is String && rawTitle.trim().isNotEmpty) {
        title = rawTitle.trim();
      }
    }

    final playIdQuery = info.bvid != null
        ? {'bvid': info.bvid!}
        : {'avid': '${info.aid}'};
    final playUri = Uri.https('api.bilibili.com', '/x/player/playurl', {
      ...playIdQuery,
      'cid': '$cid',
      'qn': '127',
      'fnval': '4048',
      'fnver': '0',
      'fourk': '1',
      'try_look': '1',
    });
    final playResponse = await _getApiJson(playUri, referer);
    final playData = _apiData(playResponse);

    final subtitles = await _loadSubtitles(
      idQuery: info.bvid != null
          ? {'bvid': info.bvid!}
          : {'aid': '${info.aid}'},
      cid: cid,
      referer: referer,
    ).timeout(_subtitleTimeout, onTimeout: () => const []);
    return _PlaybackSession.fromPlayData(
      playData,
      cid: cid,
      title: title,
      referer: referer,
      subtitles: subtitles,
    );
  }

  static int selectCid(Map<String, dynamic> viewData, int? requestedPage) {
    final pages = viewData['pages'];
    if (pages is List && pages.isNotEmpty) {
      final index = requestedPage == null ? 0 : requestedPage - 1;
      if (index >= 0 && index < pages.length) {
        final page = pages[index];
        if (page is Map && page['cid'] is num) {
          return (page['cid'] as num).toInt();
        }
      }
    }
    final cid = viewData['cid'];
    if (cid is num && cid > 0) return cid.toInt();
    throw const FormatException('Bilibili response does not contain a CID');
  }

  static Uri danmakuSegmentUri(int cid, int segment) {
    if (cid <= 0 || segment <= 0) {
      throw ArgumentError('CID and danmaku segment must be positive');
    }
    return Uri.https('api.bilibili.com', '/x/v2/dm/web/seg.so', {
      'type': '1',
      'oid': '$cid',
      'segment_index': '$segment',
    });
  }

  static Future<List<_SubtitleTrack>> _loadSubtitles({
    required Map<String, String> idQuery,
    required int cid,
    required String referer,
  }) async {
    try {
      final response = await _getApiJson(
        Uri.https('api.bilibili.com', '/x/player/v2', {
          ...idQuery,
          'cid': '$cid',
        }),
        referer,
      );
      final data = _apiData(response);
      final subtitle = data['subtitle'];
      final rawTracks = subtitle is Map ? subtitle['subtitles'] : null;
      if (rawTracks is! List) return const [];

      final tracks = <_SubtitleTrack>[];
      for (final raw in rawTracks.take(8)) {
        if (raw is! Map) continue;
        final rawUrl = raw['subtitle_url'] ?? raw['subtitleUrl'];
        if (rawUrl is! String || rawUrl.trim().isEmpty) continue;
        final uri = _normalizeBilibiliUri(rawUrl);
        if (uri == null || !_isAllowedSubtitleTarget(uri)) continue;
        try {
          final payload = await _getJson(uri, referer);
          final vtt = subtitleJsonToVtt(payload);
          if (vtt == 'WEBVTT\n\n') continue;
          tracks.add(
            _SubtitleTrack(
              language: (raw['lan'] as String?)?.trim().isNotEmpty == true
                  ? (raw['lan'] as String).trim()
                  : 'und',
              label: (raw['lan_doc'] as String?)?.trim().isNotEmpty == true
                  ? (raw['lan_doc'] as String).trim()
                  : '字幕',
              vtt: vtt,
            ),
          );
        } catch (_) {
          // One broken subtitle track must not prevent video playback.
        }
      }
      return tracks;
    } catch (_) {
      return const [];
    }
  }

  static Uri? _normalizeBilibiliUri(String rawUrl) {
    final value = rawUrl.trim();
    return Uri.tryParse(value.startsWith('//') ? 'https:$value' : value);
  }

  static bool _isAllowedSubtitleTarget(Uri target) {
    if (target.scheme != 'https' ||
        target.userInfo.isNotEmpty ||
        (target.hasPort && target.port != 443)) {
      return false;
    }
    final host = target.host.toLowerCase();
    return _isHostOrSubdomain(host, 'bilibili.com') ||
        _isHostOrSubdomain(host, 'hdslb.com');
  }

  static String subtitleJsonToVtt(Map<String, dynamic> payload) {
    final body = payload['body'];
    if (body is! List) return 'WEBVTT\n\n';
    final buffer = StringBuffer('WEBVTT\n\n');
    var cueIndex = 0;
    for (final cue in body) {
      if (cue is! Map) continue;
      final from = cue['from'];
      final to = cue['to'];
      final content = cue['content'];
      if (from is! num || to is! num || content is! String || to <= from) {
        continue;
      }
      buffer
        ..writeln(++cueIndex)
        ..writeln('${_vttTimestamp(from)} --> ${_vttTimestamp(to)}')
        ..writeln(content.replaceAll('\r\n', '\n').trim())
        ..writeln();
    }
    return buffer.toString();
  }

  static String _vttTimestamp(num seconds) {
    final milliseconds = (seconds * 1000).round().clamp(0, 1 << 53);
    final hours = milliseconds ~/ 3600000;
    final minutes = (milliseconds ~/ 60000) % 60;
    final secs = (milliseconds ~/ 1000) % 60;
    final millis = milliseconds % 1000;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')}.'
        '${millis.toString().padLeft(3, '0')}';
  }

  static Future<Map<String, dynamic>> _getApiJson(
    Uri uri,
    String referer,
  ) async {
    final payload = await _getJson(uri, referer);
    final code = payload['code'];
    if (code != 0) {
      throw HttpException(
        'Bilibili API error $code: ${payload['message']}',
        uri: uri,
      );
    }
    return payload;
  }

  static Map<String, dynamic> _apiData(Map<String, dynamic> payload) {
    final data = payload['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const FormatException('Bilibili API response has no data object');
  }

  static Future<Map<String, dynamic>> _getJson(Uri uri, String referer) async {
    final request = await _apiClient.getUrl(uri);
    request.headers
      ..set(HttpHeaders.userAgentHeader, _browserUserAgent)
      ..set(HttpHeaders.refererHeader, referer)
      ..set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException(
        'Bilibili request failed with ${response.statusCode}',
        uri: uri,
      );
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      if (bytes.length + chunk.length > _maxApiResponseBytes) {
        throw const FormatException('Bilibili API response is too large');
      }
      bytes.addAll(chunk);
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw const FormatException('Bilibili API response is not an object');
  }

  static bool _isHostOrSubdomain(String host, String domain) =>
      host == domain || host.endsWith('.$domain');

  static bool _isRedirect(int statusCode) =>
      statusCode == HttpStatus.movedPermanently ||
      statusCode == HttpStatus.found ||
      statusCode == HttpStatus.seeOther ||
      statusCode == HttpStatus.temporaryRedirect ||
      statusCode == HttpStatus.permanentRedirect;

  static Future<void> _sendText(
    HttpResponse response,
    String body,
    ContentType contentType,
  ) async {
    final bytes = utf8.encode(body);
    response.headers
      ..contentType = contentType
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('X-Content-Type-Options', 'nosniff');
    response.contentLength = bytes.length;
    response.add(bytes);
    await response.close();
  }

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
  _ServerState(this.server, this.capability);

  final HttpServer server;
  final String capability;
  final Map<String, _PlaybackSession> sessions = {};
}

final class _PlaybackSession {
  _PlaybackSession({
    required this.cid,
    required this.title,
    required this.referer,
    required this.duration,
    required this.minBufferTime,
    required this.video,
    required this.audio,
    required this.subtitles,
  }) : createdAt = DateTime.now(),
       allowedMediaUrls = {
         for (final item in [...video, ...audio])
           for (final uri in item.urls) uri.toString(),
       };

  factory _PlaybackSession.fromPlayData(
    Map<String, dynamic> playData, {
    required int cid,
    required String title,
    required String referer,
    required List<_SubtitleTrack> subtitles,
  }) {
    final dash = playData['dash'];
    if (dash is! Map) {
      throw const FormatException('Bilibili response does not contain DASH');
    }
    final duration = (dash['duration'] as num?)?.toDouble();
    if (duration == null || duration <= 0) {
      throw const FormatException('Bilibili DASH duration is invalid');
    }

    final video = _selectVideoRepresentations(dash['video']);
    final audio = _selectAudioRepresentation(dash['audio']);
    if (video.isEmpty || audio.isEmpty) {
      throw const FormatException('Bilibili DASH tracks are incomplete');
    }
    final rawMinBufferTime = dash['minBufferTime'] ?? dash['min_buffer_time'];
    return _PlaybackSession(
      cid: cid,
      title: title,
      referer: referer,
      duration: duration,
      minBufferTime: rawMinBufferTime is num
          ? rawMinBufferTime.toDouble()
          : 1.5,
      video: video,
      audio: audio,
      subtitles: subtitles,
    );
  }

  final int cid;
  final String title;
  final String referer;
  final double duration;
  final double minBufferTime;
  final List<_DashRepresentation> video;
  final List<_DashRepresentation> audio;
  final List<_SubtitleTrack> subtitles;
  final DateTime createdAt;
  final Set<String> allowedMediaUrls;

  String buildManifest(Uri Function(Uri target) mediaProxyUri) {
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" '
        'type="static" '
        'profiles="urn:mpeg:dash:profile:isoff-on-demand:2011" '
        'mediaPresentationDuration="PT${duration.toStringAsFixed(3)}S" '
        'minBufferTime="PT${minBufferTime.toStringAsFixed(3)}S">',
      )
      ..writeln('  <Period start="PT0S">')
      ..writeln(
        '    <AdaptationSet contentType="video" mimeType="video/mp4" '
        'segmentAlignment="true" startWithSAP="1">',
      );
    for (final representation in video) {
      buffer.write(representation.toXml(mediaProxyUri));
    }
    buffer
      ..writeln('    </AdaptationSet>')
      ..writeln(
        '    <AdaptationSet contentType="audio" mimeType="audio/mp4" '
        'lang="und" segmentAlignment="true" startWithSAP="1">',
      );
    for (final representation in audio) {
      buffer.write(representation.toXml(mediaProxyUri));
    }
    buffer
      ..writeln('    </AdaptationSet>')
      ..writeln('  </Period>')
      ..writeln('</MPD>');
    return buffer.toString();
  }
}

List<_DashRepresentation> _selectVideoRepresentations(Object? rawVideo) {
  if (rawVideo is! List) return const [];
  final byQuality = <int, List<_DashRepresentation>>{};
  for (final raw in rawVideo) {
    final item = _DashRepresentation.tryParse(raw, isVideo: true);
    if (item == null || !item.codecs.toLowerCase().startsWith('avc')) continue;
    (byQuality[item.id] ??= []).add(item);
  }
  final selected = <_DashRepresentation>[];
  for (final candidates in byQuality.values) {
    candidates.sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
    selected.add(candidates.first);
  }
  selected.sort((a, b) => a.height.compareTo(b.height));
  return selected;
}

List<_DashRepresentation> _selectAudioRepresentation(Object? rawAudio) {
  if (rawAudio is! List) return const [];
  final candidates =
      rawAudio
          .map((raw) => _DashRepresentation.tryParse(raw, isVideo: false))
          .whereType<_DashRepresentation>()
          .toList()
        ..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
  return candidates.isEmpty ? const [] : [candidates.first];
}

final class _DashRepresentation {
  const _DashRepresentation({
    required this.id,
    required this.bandwidth,
    required this.codecs,
    required this.width,
    required this.height,
    required this.frameRate,
    required this.indexRange,
    required this.initializationRange,
    required this.urls,
    required this.isVideo,
  });

  static _DashRepresentation? tryParse(Object? raw, {required bool isVideo}) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final bandwidth = raw['bandwidth'] ?? raw['bandWidth'];
    final codecs = raw['codecs'];
    final segmentBase = raw['segment_base'] ?? raw['SegmentBase'];
    if (id is! num ||
        bandwidth is! num ||
        codecs is! String ||
        segmentBase is! Map) {
      return null;
    }
    final indexRange = segmentBase['index_range'] ?? segmentBase['indexRange'];
    final initializationRange =
        segmentBase['initialization'] ?? segmentBase['Initialization'];
    if (indexRange is! String || initializationRange is! String) return null;

    final urls = <Uri>[];
    final primary = raw['base_url'] ?? raw['baseUrl'];
    if (primary is String) {
      final uri = Uri.tryParse(primary);
      if (uri != null && BilibiliPlaybackServer.isAllowedMediaTarget(uri)) {
        urls.add(uri);
      }
    }
    final backups = raw['backup_url'] ?? raw['backupUrl'];
    if (backups is List) {
      for (final value in backups) {
        if (value is! String) continue;
        final uri = Uri.tryParse(value);
        if (uri != null &&
            BilibiliPlaybackServer.isAllowedMediaTarget(uri) &&
            !urls.contains(uri)) {
          urls.add(uri);
        }
      }
    }
    if (urls.isEmpty) return null;

    final rawFrameRate = raw['frame_rate'] ?? raw['frameRate'];
    return _DashRepresentation(
      id: id.toInt(),
      bandwidth: bandwidth.toInt(),
      codecs: codecs,
      width: (raw['width'] as num?)?.toInt() ?? 0,
      height: (raw['height'] as num?)?.toInt() ?? 0,
      frameRate: rawFrameRate is String ? rawFrameRate.trim() : '',
      indexRange: indexRange,
      initializationRange: initializationRange,
      urls: urls,
      isVideo: isVideo,
    );
  }

  final int id;
  final int bandwidth;
  final String codecs;
  final int width;
  final int height;
  final String frameRate;
  final String indexRange;
  final String initializationRange;
  final List<Uri> urls;
  final bool isVideo;

  String toXml(Uri Function(Uri target) mediaProxyUri) {
    final idValue = _xmlAttribute('${isVideo ? 'v' : 'a'}-$id-$codecs');
    final dimensions = isVideo
        ? ' width="$width" height="$height"'
        : ' audioSamplingRate="48000"';
    final frameRateValue = isVideo && RegExp(r'^[0-9.]+$').hasMatch(frameRate)
        ? ' frameRate="${_xmlAttribute(frameRate)}"'
        : '';
    final buffer = StringBuffer()
      ..writeln(
        '      <Representation id="$idValue" bandwidth="$bandwidth" '
        'codecs="${_xmlAttribute(codecs)}"$dimensions$frameRateValue>',
      );
    for (var index = 0; index < urls.length; index++) {
      buffer.writeln(
        '        <BaseURL serviceLocation="cdn-$index">'
        '${_xmlText(mediaProxyUri(urls[index]).toString())}</BaseURL>',
      );
    }
    buffer
      ..writeln(
        '        <SegmentBase indexRange="${_xmlAttribute(indexRange)}">',
      )
      ..writeln(
        '          <Initialization '
        'range="${_xmlAttribute(initializationRange)}"/>',
      )
      ..writeln('        </SegmentBase>')
      ..writeln('      </Representation>');
    return buffer.toString();
  }
}

final class _SubtitleTrack {
  const _SubtitleTrack({
    required this.language,
    required this.label,
    required this.vtt,
  });

  final String language;
  final String label;
  final String vtt;
}

String _xmlAttribute(String value) =>
    const HtmlEscape(HtmlEscapeMode.attribute).convert(value);

String _xmlText(String value) =>
    const HtmlEscape(HtmlEscapeMode.element).convert(value);
