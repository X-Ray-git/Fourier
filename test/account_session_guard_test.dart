import 'package:fourier/services/account_session_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('account transition invalidates work on both boundaries', () {
    final before = AccountSessionGuard.revision;
    expect(AccountSessionGuard.isCurrent(before), isTrue);

    final during = AccountSessionGuard.beginAccountChange();
    expect(AccountSessionGuard.isTransitioning, isTrue);
    expect(AccountSessionGuard.isCurrent(before), isFalse);
    expect(AccountSessionGuard.isCurrent(during), isFalse);

    final after = AccountSessionGuard.finishAccountChange();
    expect(AccountSessionGuard.isTransitioning, isFalse);
    expect(AccountSessionGuard.isCurrent(during), isFalse);
    expect(AccountSessionGuard.isCurrent(after), isTrue);
  });
}
