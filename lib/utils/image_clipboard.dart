import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ImageClipboard {
  static const int maxDownloadBytes = 32 * 1024 * 1024;

  static const _channel = MethodChannel(
    'io.github.xraygit.fourier/image_clipboard',
  );

  static Future<Uint8List?> downloadBytes(
    String url, {
    int maxBytes = maxDownloadBytes,
  }) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    try {
      final response = await dio.get<ResponseBody>(
        url,
        options: Options(responseType: ResponseType.stream),
      );
      final body = response.data;
      if (body == null) return null;

      final lengthHeaders = body.headers['content-length'];
      final declaredLength = int.tryParse(
        lengthHeaders == null || lengthHeaders.isEmpty
            ? ''
            : lengthHeaders.first,
      );
      if (declaredLength != null && declaredLength > maxBytes) return null;

      final bytes = BytesBuilder(copy: false);
      var received = 0;
      await for (final chunk in body.stream) {
        received += chunk.length;
        if (received > maxBytes) return null;
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    } catch (_) {
      return null;
    } finally {
      dio.close(force: true);
    }
  }

  static Future<bool> copyImageToClipboard(Uint8List imageBytes) async {
    if (!Platform.isMacOS) return false;
    try {
      await _channel.invokeMethod('copyImage', imageBytes);
      return true;
    } catch (e) {
      debugPrint('Failed to copy image to clipboard: $e');
      return false;
    }
  }
}
