import 'package:flutter_test/flutter_test.dart';

import 'package:autofolo/common/constants/constants.dart';
import 'package:autofolo/services/settings_backup_service.dart';

void main() {
  group('SettingsBackupService.summarize', () {
    test('treats a session token as complete Folo credentials', () {
      final summary = SettingsBackupService.summarize({
        StorageKeys.sessionToken: 'token',
      });

      expect(summary.hasFoloCredentials, isTrue);
      expect(summary.containsSensitiveData, isTrue);
    });

    test('does not treat legacy client and session ids as credentials', () {
      final summary = SettingsBackupService.summarize({
        StorageKeys.clientId: 'client',
        StorageKeys.sessionId: 'session',
      });

      expect(summary.hasFoloCredentials, isFalse);
      expect(summary.containsSensitiveData, isFalse);
    });
  });
}
