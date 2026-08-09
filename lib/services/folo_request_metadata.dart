import 'dart:io';
import 'dart:math';

import '../common/constants/constants.dart';
import '../utils/storage.dart';
import 'app_version_service.dart';

/// Folo protocol metadata generated and managed internally by Fourier.
abstract final class FoloRequestMetadata {
  static late final String clientId;
  static late final String sessionId;

  static Map<String, String> get protocolHeaders => {
    'Cache-Control': 'no-store',
    'User-Agent': _userAgent,
    'X-App-Platform': _appPlatform,
    'X-App-Name': AppConstants.appName,
    'X-App-Version': AppVersionService.version,
    'X-Client-Id': clientId,
    'X-Session-Id': sessionId,
  };

  static Future<void> init() async {
    final stored = GStorage.setting.get(StorageKeys.foloClientId);
    if (stored is String && _isUuid(stored)) {
      clientId = stored;
    } else {
      clientId = _newUuid();
      await GStorage.setting.put(StorageKeys.foloClientId, clientId);
    }
    sessionId = _newUuid();
  }

  static bool _isUuid(String value) => RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  ).hasMatch(value);

  static String get _appPlatform {
    if (Platform.isMacOS) return 'desktop/macos/dmg';
    if (Platform.isAndroid) return 'mobile/android/apk';
    return 'unknown';
  }

  static String get _userAgent {
    final platform = Platform.isMacOS ? 'macOS' : Platform.operatingSystem;
    return '${AppConstants.appName}/${AppVersionService.version} ($platform)';
  }

  static String _newUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
