/// Rejects asynchronous work that belongs to a previous local account session.
abstract final class AccountSessionGuard {
  static int _revision = 0;
  static bool _transitioning = false;

  static int get revision => _revision;
  static bool get isTransitioning => _transitioning;

  static int invalidate() => ++_revision;

  static int beginAccountChange() {
    _transitioning = true;
    return invalidate();
  }

  static int finishAccountChange() {
    _transitioning = false;
    return invalidate();
  }

  static bool isCurrent(int revision) =>
      !_transitioning && revision == _revision;
}
