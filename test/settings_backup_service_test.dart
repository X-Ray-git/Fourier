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

  group('SettingsBackupService.parseJson', () {
    test('keeps a version 1 session token for migration', () {
      final payload = SettingsBackupService.parseJson('''
{
  "type": "auto_folo_settings",
  "version": 1,
  "settings": {
    "session_token": "existing-token",
    "summary_prompt": "prompt",
    "client_id": "legacy-client"
  }
}
''');

      expect(payload.sessionToken, 'existing-token');
      expect(payload.settings['summary_prompt'], 'prompt');
      expect(payload.settings, isNot(contains(StorageKeys.clientId)));
      expect(payload.summary.hasFoloCredentials, isTrue);
    });

    test('rejects unsupported backup versions before applying settings', () {
      expect(
        () => SettingsBackupService.parseJson('''
{"type":"auto_folo_settings","version":2,"settings":{}}
'''),
        throwsFormatException,
      );
    });
  });
}
