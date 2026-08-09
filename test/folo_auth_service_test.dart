import 'package:fourier/services/folo_auth_service.dart';
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

  group('FoloAuthService Android social login helpers', () {
    test('uses the Fourier Android callback URI', () {
      expect(
        FoloAuthService.androidAuthCallbackUri,
        Uri.parse('folo://fourier-auth'),
      );
    });

    test('parses the provider list returned by Folo', () {
      final providers = FoloAuthService.authProvidersFromResponse({
        'google': {'id': 'google', 'name': 'Google'},
        'github': {'id': 'github', 'name': 'GitHub'},
        'credential': {'id': 'credential', 'name': 'Email'},
        'invalid': {'id': '', 'name': 'Invalid'},
      });

      expect(providers.map((provider) => provider.id), [
        'google',
        'github',
        'credential',
      ]);
      expect(providers.last.isCredential, isTrue);
    });

    test('keeps a local Android provider fallback', () {
      expect(
        FoloAuthService.androidFallbackAuthProviders.map(
          (provider) => provider.id,
        ),
        ['credential', 'google', 'github'],
      );
    });

    test('builds the Better Auth Expo authorization proxy URL', () {
      final uri = FoloAuthService.androidAuthorizationProxyUri(
        authorizationUrl: 'https://accounts.google.com/o/oauth2/v2/auth?a=1',
      );

      expect(uri.host, 'api.folo.is');
      expect(uri.path, '/better-auth/expo-authorization-proxy');
      expect(
        uri.queryParameters['authorizationURL'],
        'https://accounts.google.com/o/oauth2/v2/auth?a=1',
      );
      expect(uri.queryParameters.containsKey('oauthState'), isFalse);
    });

    test('extracts the session token from an Expo callback cookie', () {
      expect(
        FoloAuthService.sessionTokenFromCookieHeader(
          '__Secure-better-auth.session_token=abc.def%3D; Path=/; Secure',
        ),
        'abc.def%3D',
      );
      expect(
        FoloAuthService.sessionTokenFromCookieHeader('other=value; Path=/'),
        isNull,
      );
    });
  });

  test('account candidate prefers name and falls back to email', () {
    const named = FoloAccountCandidate(
      sessionToken: 'token',
      name: 'X-Ray',
      email: 'x@example.com',
      imageUrl: 'https://example.com/avatar.png',
    );
    const emailOnly = FoloAccountCandidate(
      sessionToken: 'token',
      email: 'x@example.com',
    );

    expect(named.displayName, 'X-Ray');
    expect(named.profile.imageUrl, 'https://example.com/avatar.png');
    expect(emailOnly.displayName, 'x@example.com');
  });

  test('rejects malformed session tokens as credential errors', () async {
    await expectLater(
      FoloAuthService.validateSessionToken('invalid;cookie'),
      throwsA(
        isA<FoloAuthException>().having(
          (error) => error.kind,
          'kind',
          FoloAuthFailureKind.invalidCredential,
        ),
      ),
    );
  });
}
