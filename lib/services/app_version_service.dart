import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

abstract final class AppVersionService {
  static String _version = '0.0.0';
  static String _buildNumber = '';

  static String get version => _version;
  static String get buildNumber => _buildNumber;

  static Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _version = info.version;
      _buildNumber = info.buildNumber;
    } catch (error) {
      debugPrint('AppVersion init skipped: $error');
    }
  }
}
