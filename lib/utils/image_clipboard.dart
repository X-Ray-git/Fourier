import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ImageClipboard {
  static const _channel = MethodChannel(
    'io.github.xraygit.fourier/image_clipboard',
  );

  static Future<Uint8List?> downloadBytes(String url) async {
    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      final response = await dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      if (response.data != null) {
        return Uint8List.fromList(response.data!);
      }
      return null;
    } catch (_) {
      return null;
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
