import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common/constants/constants.dart';
import '../utils/security_utils.dart';

class FoloAccountCandidate {
  const FoloAccountCandidate({
    required this.sessionToken,
    this.userId,
    this.name,
    this.email,
  });

  final String sessionToken;
  final String? userId;
  final String? name;
  final String? email;

  String get displayName {
    final resolvedName = name?.trim();
    if (resolvedName != null && resolvedName.isNotEmpty) return resolvedName;
    final resolvedEmail = email?.trim();
    if (resolvedEmail != null && resolvedEmail.isNotEmpty) return resolvedEmail;
    return 'Folo 账号';
  }
}

class FoloAuthException implements Exception {
  const FoloAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract final class FoloAuthService {
  static const _applyPath = '/better-auth/one-time-token/apply';
  static const _verifyPath = '/better-auth/one-time-token/verify';
  static const _sessionPath = '/better-auth/get-session';

  static Dio _createDio() => Dio(
    BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      validateStatus: (_) => true,
      headers: const {'Accept': 'application/json'},
    ),
  );

  static Uri browserLoginUri(Uri callbackUri) {
    return Uri.https('app.folo.is', '/login', {
      'cli_callback': callbackUri.toString(),
    });
  }

  static Future<FoloAccountCandidate> validateSessionToken(String token) async {
    final normalized = SecurityUtils.normalizeCredential(token);
    if (normalized.isEmpty || !SecurityUtils.isSafeCookieValue(normalized)) {
      throw const FoloAuthException('Session Token 格式不合法');
    }

    final dio = _createDio();
    try {
      final response = await dio.get(
        _sessionPath,
        options: Options(
          headers: {
            'Authorization': 'Bearer $normalized',
            'Cookie':
                '__Secure-better-auth.session_token=$normalized; '
                'better-auth.session_token=$normalized',
          },
        ),
      );
      final body = _asStringMap(response.data);
      final user = _asStringMap(body?['user']);
      final session = _asStringMap(body?['session']);
      if (response.statusCode != 200 || user == null || session == null) {
        throw const FoloAuthException('Folo 登录凭据无效或已经过期');
      }
      return FoloAccountCandidate(
        sessionToken: normalized,
        userId: user['id']?.toString(),
        name: user['name']?.toString(),
        email: user['email']?.toString(),
      );
    } on DioException catch (error) {
      throw FoloAuthException(_networkMessage(error));
    } finally {
      dio.close(force: true);
    }
  }

  static Future<FoloAccountCandidate> exchangeOneTimeToken(String token) async {
    final normalized = SecurityUtils.normalizeCredential(token);
    if (normalized.isEmpty) {
      throw const FoloAuthException('浏览器没有返回登录凭据');
    }

    final dio = _createDio();
    try {
      var response = await dio.post(_applyPath, data: {'token': normalized});
      if (response.statusCode == 404) {
        response = await dio.post(_verifyPath, data: {'token': normalized});
      }
      if ((response.statusCode ?? 500) >= 200 &&
          (response.statusCode ?? 500) < 300) {
        final sessionToken = _extractSessionToken(response);
        if (sessionToken != null && sessionToken.isNotEmpty) {
          return validateSessionToken(sessionToken);
        }
      }

      // Folo CLI also accepts a long-lived session token as a fallback.
      try {
        return await validateSessionToken(normalized);
      } on FoloAuthException {
        final body = _asStringMap(response.data);
        final message = body?['message']?.toString().trim();
        throw FoloAuthException(
          message == null || message.isEmpty ? '浏览器登录凭据验证失败' : message,
        );
      }
    } on DioException catch (error) {
      throw FoloAuthException(_networkMessage(error));
    } finally {
      dio.close(force: true);
    }
  }

  static Future<FoloBrowserLoginSession> startBrowserLogin({
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final callbackUri = Uri.parse('http://127.0.0.1:${server.port}/callback');
    final session = FoloBrowserLoginSession._(
      server,
      callbackUri: callbackUri,
      loginUri: browserLoginUri(callbackUri),
      timeout: timeout,
    );
    session._start();
    await session.openBrowser();
    return session;
  }

  static String? _extractSessionToken(Response<dynamic> response) {
    for (final cookie
        in response.headers.map['set-cookie'] ?? const <String>[]) {
      final match = RegExp(
        r'(?:__Secure-)?better-auth\.session_token=([^;]+)',
      ).firstMatch(cookie);
      if (match != null) return match.group(1);
    }
    final body = _asStringMap(response.data);
    final session = _asStringMap(body?['session']);
    return session?['token']?.toString();
  }

  static Map<String, dynamic>? _asStringMap(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static String _networkMessage(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return '连接 Folo 超时';
    }
    return '无法连接 Folo 服务';
  }
}

class FoloBrowserLoginSession {
  FoloBrowserLoginSession._(
    this._server, {
    required this.callbackUri,
    required this.loginUri,
    required this._timeout,
  });

  final HttpServer _server;
  final Duration _timeout;
  final Uri callbackUri;
  final Uri loginUri;
  final Completer<FoloAccountCandidate> _completer = Completer();
  Timer? _timer;
  bool _closed = false;

  Future<FoloAccountCandidate> get result => _completer.future;

  Future<bool> openBrowser() {
    return launchUrl(loginUri, mode: LaunchMode.externalApplication);
  }

  void _start() {
    _timer = Timer(_timeout, () {
      _completeError(const FoloAuthException('等待浏览器登录超时，请重试'));
    });
    unawaited(_listen());
  }

  Future<void> _listen() async {
    try {
      await for (final request in _server) {
        if (request.uri.path != '/callback') {
          await _respond(request.response, 404, 'Not Found');
          continue;
        }
        final token = request.uri.queryParameters['token'];
        if (token == null || token.trim().isEmpty) {
          await _respondHtml(request.response, false);
          continue;
        }
        try {
          final candidate = await FoloAuthService.exchangeOneTimeToken(token);
          await _respondHtml(request.response, true);
          await _complete(candidate);
        } catch (error) {
          await _respondHtml(request.response, false);
          await _completeError(error);
        }
        return;
      }
    } catch (error) {
      await _completeError(FoloAuthException('本地登录回调失败：$error'));
    }
  }

  Future<void> cancel() async {
    await _completeError(const FoloAuthException('已取消浏览器登录'));
  }

  Future<void> _complete(FoloAccountCandidate candidate) async {
    if (_closed) return;
    _completer.complete(candidate);
    await _close();
  }

  Future<void> _completeError(Object error) async {
    if (_closed) return;
    _completer.completeError(error);
    await _close();
  }

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    await _server.close(force: true);
  }

  static Future<void> _respond(
    HttpResponse response,
    int status,
    String text,
  ) async {
    response
      ..statusCode = status
      ..headers.contentType = ContentType.text
      ..headers.set(HttpHeaders.connectionHeader, 'close')
      ..write(text);
    await response.close();
  }

  static Future<void> _respondHtml(HttpResponse response, bool success) async {
    final title = success ? 'Auto Folo 登录完成' : 'Auto Folo 登录失败';
    final message = success
        ? '可以关闭此页面并返回 Auto Folo。'
        : '回调中缺少登录凭据，请返回 Auto Folo 重试。';
    final html =
        '<!doctype html><html lang="zh-CN"><head>'
        '<meta charset="utf-8"><meta name="viewport" '
        'content="width=device-width,initial-scale=1"><title>$title</title>'
        '</head><body style="font-family:-apple-system,BlinkMacSystemFont,'
        'sans-serif;padding:32px;line-height:1.6"><h1>$title</h1>'
        '<p>$message</p></body></html>';
    response
      ..statusCode = success ? 200 : 400
      ..headers.contentType = ContentType.html
      ..headers.set(HttpHeaders.connectionHeader, 'close')
      ..write(html);
    await response.close();
  }
}
