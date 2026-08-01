import 'package:autofolo/models/folo_account_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('account profile survives local serialization', () {
    const profile = FoloAccountProfile(
      userId: 'user-id',
      name: 'X-Ray',
      email: 'x@example.com',
      imageUrl: 'https://example.com/avatar.png',
    );

    final restored = FoloAccountProfile.fromJson(profile.toJson());

    expect(restored?.userId, 'user-id');
    expect(restored?.displayName, 'X-Ray');
    expect(restored?.initials, 'X');
    expect(restored?.imageUrl, 'https://example.com/avatar.png');
  });

  test('account profile falls back to email and ignores empty storage', () {
    final profile = FoloAccountProfile.fromJson({
      'name': '  ',
      'email': 'reader@example.com',
    });

    expect(profile?.displayName, 'reader@example.com');
    expect(FoloAccountProfile.fromJson(const {}), isNull);
  });
}
