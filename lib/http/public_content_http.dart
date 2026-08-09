import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../common/constants/constants.dart';

/// Unauthenticated client for fetching public article pages.
///
/// This client must never receive Folo credentials or API-specific headers.
abstract final class PublicContentHttp {
  static final Dio dio = _createDio();

  static Dio _createDio() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(
          milliseconds: AppConstants.defaultTimeout,
        ),
        receiveTimeout: const Duration(
          milliseconds: AppConstants.defaultTimeout,
        ),
        sendTimeout: const Duration(milliseconds: AppConstants.defaultTimeout),
        headers: {
          'Accept': 'text/html,application/xhtml+xml',
          'User-Agent': _browserUserAgent,
        },
      ),
    );
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () =>
          HttpClient()..idleTimeout = const Duration(seconds: 15),
    );
    return dio;
  }

  static String get _browserUserAgent {
    if (Platform.isAndroid) {
      return 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/133.0.0.0 Mobile Safari/537.36';
    }
    return 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
        'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 '
        'Safari/537.36';
  }
}
