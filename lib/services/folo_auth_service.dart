import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common/constants/constants.dart';
import '../models/folo_account_profile.dart';
import '../utils/security_utils.dart';
import 'folo_request_metadata.dart';

class FoloAccountCandidate {
  const FoloAccountCandidate({
    required this.sessionToken,
    this.userId,
    this.name,
    this.email,
    this.imageUrl,
  });

  final String sessionToken;
  final String? userId;
  final String? name;
  final String? email;
  final String? imageUrl;

  FoloAccountProfile get profile => FoloAccountProfile(
    userId: userId,
    name: name,
    email: email,
    imageUrl: imageUrl,
  );

  String get displayName => profile.displayName;
}

enum FoloAuthFailureKind { unknown, invalidCredential, network }

class FoloAuthException implements Exception {
  const FoloAuthException(
    this.message, {
    this.kind = FoloAuthFailureKind.unknown,
  });

  final String message;
  final FoloAuthFailureKind kind;

  @override
  String toString() => message;
}

class FoloAuthProvider {
  const FoloAuthProvider({required this.id, required this.name});

  final String id;
  final String name;

  bool get isCredential => id == 'credential';
}

class FoloEmailLoginResult {
  const FoloEmailLoginResult._({this.candidate, this.twoFactorCookie});

  const FoloEmailLoginResult.authenticated(FoloAccountCandidate candidate)
    : this._(candidate: candidate);

  const FoloEmailLoginResult.twoFactorRequired(String cookie)
    : this._(twoFactorCookie: cookie);

  final FoloAccountCandidate? candidate;
  final String? twoFactorCookie;

  bool get requiresTwoFactor => twoFactorCookie != null;
}

abstract interface class FoloLoginSession {
  Uri get loginUri;

  Future<FoloAccountCandidate> get result;

  Future<bool> openBrowser();

  Future<void> cancel();
}

abstract final class FoloAuthService {
  static const _applyPath = '/better-auth/one-time-token/apply';
  static const _verifyPath = '/better-auth/one-time-token/verify';
  static const _sessionPath = '/better-auth/get-session';
  static const _providersPath = '/better-auth/get-providers';
  static const _socialSignInPath = '/better-auth/sign-in/social';
  static const _emailSignInPath = '/better-auth/sign-in/email';
  static const _verifyTotpPath = '/better-auth/two-factor/verify-totp';
  static const _expoAuthorizationProxyPath =
      '/better-auth/expo-authorization-proxy';

  static final Uri androidAuthCallbackUri = Uri.parse('folo://fourier-auth');
  static const androidFallbackAuthProviders = <FoloAuthProvider>[
    FoloAuthProvider(id: 'credential', name: 'Email'),
    FoloAuthProvider(id: 'google', name: 'Google'),
    FoloAuthProvider(id: 'github', name: 'GitHub'),
  ];

  static void _debugProbe(String message) {
    if (kDebugMode) debugPrint('[FoloAuthProbe] $message');
  }

  static Dio _createDio() => Dio(
    BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      followRedirects: false,
      validateStatus: (_) => true,
      headers: {
        'Accept': 'application/json',
        ...FoloRequestMetadata.protocolHeaders,
      },
    ),
  );

  static Uri browserLoginUri(Uri callbackUri) {
    return Uri.https('app.folo.is', '/login', {
      'cli_callback': callbackUri.toString(),
    });
  }

  static Uri androidAuthorizationProxyUri({required String authorizationUrl}) {
    return Uri.parse(
      '${ApiConstants.baseUrl}$_expoAuthorizationProxyPath',
    ).replace(queryParameters: {'authorizationURL': authorizationUrl});
  }

  static String? sessionTokenFromCookieHeader(String? cookieHeader) {
    if (cookieHeader == null || cookieHeader.isEmpty) return null;
    return RegExp(
      r'(?:__Secure-)?better-auth\.session_token=([^;]+)',
    ).firstMatch(cookieHeader)?.group(1);
  }

  static List<FoloAuthProvider> authProvidersFromResponse(Object? data) {
    final providers = _asStringMap(data);
    if (providers == null) return const [];
    return providers.values
        .map(_asStringMap)
        .whereType<Map<String, dynamic>>()
        .map((provider) {
          final id = provider['id']?.toString().trim() ?? '';
          final name = provider['name']?.toString().trim() ?? '';
          if (id.isEmpty || name.isEmpty) return null;
          return FoloAuthProvider(id: id, name: name);
        })
        .whereType<FoloAuthProvider>()
        .toList(growable: false);
  }

  static Future<List<FoloAuthProvider>> fetchAuthProviders() async {
    final dio = _createDio();
    try {
      final response = await dio.get(_providersPath);
      final providers = authProvidersFromResponse(response.data);
      if (response.statusCode != 200 || providers.isEmpty) {
        _debugProbe(
          'Provider discovery returned status=${response.statusCode}; '
          'using fallback providers',
        );
        return androidFallbackAuthProviders;
      }
      return providers;
    } on DioException catch (error) {
      _debugProbe(
        'Provider discovery failed type=${error.type.name} '
        'status=${error.response?.statusCode}; using fallback providers',
      );
      return androidFallbackAuthProviders;
    } finally {
      dio.close(force: true);
    }
  }

  static Future<FoloAccountCandidate> validateSessionToken(String token) async {
    final normalized = SecurityUtils.normalizeCredential(token);
    if (normalized.isEmpty || !SecurityUtils.isSafeCookieValue(normalized)) {
      throw const FoloAuthException(
        'Session Token 格式不合法',
        kind: FoloAuthFailureKind.invalidCredential,
      );
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
        throw const FoloAuthException(
          'Folo 登录凭据无效或已经过期',
          kind: FoloAuthFailureKind.invalidCredential,
        );
      }
      return FoloAccountCandidate(
        sessionToken: normalized,
        userId: user['id']?.toString(),
        name: user['name']?.toString(),
        email: user['email']?.toString(),
        imageUrl: user['image']?.toString(),
      );
    } on DioException catch (error) {
      throw FoloAuthException(
        _networkMessage(error),
        kind: FoloAuthFailureKind.network,
      );
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
    final loginUri = browserLoginUri(callbackUri);
    _debugProbe(
      'macOS browser login prepared callbackHost=${callbackUri.host} '
      'callbackPort=${callbackUri.port} '
      'loginHost=${loginUri.host} '
      'hasCliCallback=${loginUri.queryParameters.containsKey('cli_callback')}',
    );
    final session = FoloBrowserLoginSession._(
      server,
      callbackUri: callbackUri,
      loginUri: loginUri,
      timeout: timeout,
    );
    session._start();
    final opened = await session.openBrowser();
    _debugProbe('macOS system browser open result=$opened');
    return session;
  }

  static Future<FoloLoginSession> startPlatformLogin({
    Duration timeout = const Duration(minutes: 3),
  }) {
    if (Platform.isAndroid) {
      throw const FoloAuthException('Android 登录需要先选择登录方式');
    }
    return startBrowserLogin(timeout: timeout);
  }

  static Future<FoloAndroidSocialLoginSession> startAndroidSocialLogin({
    required String providerId,
    required String providerName,
    Duration timeout = const Duration(minutes: 3),
  }) async {
    if (!Platform.isAndroid) {
      throw const FoloAuthException('Android 社交登录只能在 Android 设备上使用');
    }

    final normalizedProviderId = providerId.trim();
    final normalizedProviderName = providerName.trim();
    if (normalizedProviderId.isEmpty || normalizedProviderId == 'credential') {
      throw const FoloAuthException('Folo 登录方式无效');
    }

    final dio = _createDio();
    try {
      final response = await dio.post(
        _socialSignInPath,
        data: {
          'provider': normalizedProviderId,
          'callbackURL': androidAuthCallbackUri.toString(),
        },
        options: Options(
          headers: const {
            'Content-Type': 'application/json',
            'expo-origin': 'folo://',
            'x-skip-oauth-proxy': 'true',
          },
        ),
      );
      final body = _asStringMap(response.data);
      final authorizationUrl = body?['url']?.toString();
      if (response.statusCode != 200 ||
          authorizationUrl == null ||
          authorizationUrl.isEmpty) {
        final message = body?['message']?.toString().trim();
        throw FoloAuthException(
          message == null || message.isEmpty
              ? '无法启动 Folo $normalizedProviderName 登录'
              : message,
        );
      }

      _debugProbe('Android $normalizedProviderId authorization prepared');
      final session = FoloAndroidSocialLoginSession._(
        timeout,
        callbackUri: androidAuthCallbackUri,
        loginUri: androidAuthorizationProxyUri(
          authorizationUrl: authorizationUrl,
        ),
        providerName: normalizedProviderName,
      );
      await session.start();
      await session.openBrowser();
      _debugProbe('Android system browser opened');
      return session;
    } on DioException catch (error) {
      throw FoloAuthException(_networkMessage(error));
    } finally {
      dio.close(force: true);
    }
  }

  static Future<FoloEmailLoginResult> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty || !normalizedEmail.contains('@')) {
      throw const FoloAuthException('请输入有效的邮箱地址');
    }
    if (password.length < 8 || password.length > 128) {
      throw const FoloAuthException('密码长度应为 8 至 128 个字符');
    }

    final dio = _createDio();
    try {
      final response = await dio.post(
        _emailSignInPath,
        data: {'email': normalizedEmail, 'password': password},
        options: Options(
          headers: const {
            'Content-Type': 'application/json',
            'x-token': 'ac:fallback',
          },
        ),
      );
      final body = _asStringMap(response.data);
      if (response.statusCode != 200) {
        throw FoloAuthException(
          _responseMessage(response.data, fallback: '邮箱或密码不正确'),
        );
      }

      if (body?['twoFactorRedirect'] == true) {
        final cookie = _extractCookie(response, const [
          'better-auth.two_factor',
          '__Secure-better-auth.two_factor',
        ]);
        if (cookie == null) {
          throw const FoloAuthException('Folo 未返回二步验证凭据，请重试');
        }
        return FoloEmailLoginResult.twoFactorRequired(cookie);
      }

      final sessionToken = _extractSessionToken(response);
      if (sessionToken == null || sessionToken.isEmpty) {
        throw const FoloAuthException('Folo 未返回 Session Token');
      }
      return FoloEmailLoginResult.authenticated(
        await validateSessionToken(sessionToken),
      );
    } on DioException catch (error) {
      throw FoloAuthException(_networkMessage(error));
    } finally {
      dio.close(force: true);
    }
  }

  static Future<FoloAccountCandidate> verifyEmailTotp({
    required String code,
    required String twoFactorCookie,
  }) async {
    final normalizedCode = code.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(normalizedCode)) {
      throw const FoloAuthException('请输入 6 位二步验证码');
    }

    final dio = _createDio();
    try {
      final response = await dio.post(
        _verifyTotpPath,
        data: {'code': normalizedCode},
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Cookie': twoFactorCookie,
          },
        ),
      );
      if (response.statusCode != 200) {
        throw FoloAuthException(
          _responseMessage(response.data, fallback: '二步验证码无效'),
        );
      }
      final sessionToken = _extractSessionToken(response);
      if (sessionToken == null || sessionToken.isEmpty) {
        throw const FoloAuthException('Folo 未返回 Session Token');
      }
      return validateSessionToken(sessionToken);
    } on DioException catch (error) {
      throw FoloAuthException(_networkMessage(error));
    } finally {
      dio.close(force: true);
    }
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
    return session?['token']?.toString() ?? body?['token']?.toString();
  }

  static String? _extractCookie(
    Response<dynamic> response,
    List<String> names,
  ) {
    for (final rawCookie
        in response.headers.map['set-cookie'] ?? const <String>[]) {
      for (final name in names) {
        final match = RegExp(
          '(?:^|,\\s*)${RegExp.escape(name)}=([^;,]+)',
        ).firstMatch(rawCookie);
        if (match != null) return '$name=${match.group(1)}';
      }
    }
    return null;
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

  static String _responseMessage(Object? data, {required String fallback}) {
    final body = _asStringMap(data);
    final direct = body?['message']?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final nested = _asStringMap(body?['error']);
    final nestedMessage = nested?['message']?.toString().trim();
    return nestedMessage == null || nestedMessage.isEmpty
        ? fallback
        : nestedMessage;
  }
}

class FoloBrowserLoginSession implements FoloLoginSession {
  FoloBrowserLoginSession._(
    this._server, {
    required this.callbackUri,
    required this.loginUri,
    required this._timeout,
  });

  final HttpServer _server;
  final Duration _timeout;
  final Uri callbackUri;
  @override
  final Uri loginUri;
  final Completer<FoloAccountCandidate> _completer = Completer();
  Timer? _timer;
  bool _closed = false;

  @override
  Future<FoloAccountCandidate> get result => _completer.future;

  @override
  Future<bool> openBrowser() {
    return launchUrl(loginUri, mode: LaunchMode.externalApplication);
  }

  void _start() {
    _timer = Timer(_timeout, () {
      FoloAuthService._debugProbe('macOS browser login timed out');
      _completeError(const FoloAuthException('等待浏览器登录超时，请重试'));
    });
    unawaited(_listen());
  }

  Future<void> _listen() async {
    try {
      await for (final request in _server) {
        FoloAuthService._debugProbe(
          'macOS callback received method=${request.method} '
          'path=${request.uri.path} '
          'hasToken=${request.uri.queryParameters.containsKey('token')}',
        );
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

  @override
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
    final title = success
        ? '${AppConstants.appName} 登录完成'
        : '${AppConstants.appName} 登录失败';
    final message = success
        ? '可以关闭此页面并返回 ${AppConstants.appName}。'
        : '回调中缺少登录凭据，请返回 ${AppConstants.appName} 重试。';
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

class FoloAndroidSocialLoginSession implements FoloLoginSession {
  FoloAndroidSocialLoginSession._(
    this._timeout, {
    required this.callbackUri,
    required this.loginUri,
    required this.providerName,
  });

  static const _channel = MethodChannel(
    'io.github.xraygit.fourier/auth_callback',
  );

  final Uri callbackUri;
  final String providerName;
  @override
  final Uri loginUri;
  final Duration _timeout;
  final Completer<FoloAccountCandidate> _completer = Completer();
  Timer? _timer;
  bool _closed = false;

  @override
  Future<FoloAccountCandidate> get result => _completer.future;

  Future<void> start() async {
    _timer = Timer(_timeout, () {
      unawaited(_completeError(const FoloAuthException('等待浏览器登录超时，请重试')));
    });
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onAuthCallback' || call.arguments is! String) {
        return false;
      }
      return _handleCallback(call.arguments as String);
    });
    final pending = await _channel.invokeMethod<String>(
      'takePendingAuthCallback',
    );
    if (pending != null) await _handleCallback(pending);
  }

  @override
  Future<bool> openBrowser() {
    return launchUrl(loginUri, mode: LaunchMode.externalApplication);
  }

  Future<bool> _handleCallback(String rawUri) async {
    if (_closed) return false;
    final uri = Uri.tryParse(rawUri);
    if (uri == null ||
        uri.scheme != callbackUri.scheme ||
        uri.host != callbackUri.host) {
      return false;
    }
    FoloAuthService._debugProbe('Android auth callback received');

    final error = uri.queryParameters['error'];
    if (error != null && error.isNotEmpty) {
      await _completeError(FoloAuthException('Folo 登录失败：$error'));
      return true;
    }
    final sessionToken = FoloAuthService.sessionTokenFromCookieHeader(
      uri.queryParameters['cookie'],
    );
    if (sessionToken == null || sessionToken.isEmpty) {
      FoloAuthService._debugProbe('Android callback has no session cookie');
      await _completeError(
        const FoloAuthException('Folo 登录回调中缺少 Session Token'),
      );
      return true;
    }

    try {
      final candidate = await FoloAuthService.validateSessionToken(
        sessionToken,
      );
      FoloAuthService._debugProbe('Android session token validated');
      await _complete(candidate);
    } catch (error) {
      await _completeError(error);
    }
    return true;
  }

  @override
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
    _channel.setMethodCallHandler(null);
    try {
      await _channel.invokeMethod<void>('clearPendingAuthCallback');
    } on PlatformException {
      // Cleanup must not turn an already completed login result into an error.
    } on MissingPluginException {
      // Tests and unsupported platforms do not install the Android channel.
    }
  }
}
