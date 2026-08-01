import 'package:autofolo/services/folo_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FoloAuthService.browserLoginUri', () {
    test('uses the official login page and localhost callback', () {
      final callback = Uri.parse('http://127.0.0.1:32123/callback');
      final login = FoloAuthService.browserLoginUri(callback);

      expect(login.scheme, 'https');
      expect(login.host, 'app.folo.is');
      expect(login.path, '/login');
      expect(login.queryParameters['cli_callback'], callback.toString());
    });
  });

  test('account candidate prefers name and falls back to email', () {
    const named = FoloAccountCandidate(
      sessionToken: 'token',
      name: 'X-Ray',
      email: 'x@example.com',
    );
    const emailOnly = FoloAccountCandidate(
      sessionToken: 'token',
      email: 'x@example.com',
    );

    expect(named.displayName, 'X-Ray');
    expect(emailOnly.displayName, 'x@example.com');
  });
}
