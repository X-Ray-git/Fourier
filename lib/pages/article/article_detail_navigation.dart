import 'package:flutter/widgets.dart';

/// Owns related-route state for one detail pane. Route callbacks cannot pop a
/// different article or publish state after this pane has been replaced.
class ArticleDetailNavigation extends NavigatorObserver {
  ArticleDetailNavigation(this.onRelatedChanged);

  final ValueChanged<bool> onRelatedChanged;
  final List<Route<dynamic>> _routes = [];
  final Set<Route<dynamic>> _scheduledPops = {};
  final Set<Route<dynamic>> _requestedPops = {};
  bool _disposed = false;
  bool _related = false;

  void _publish() {
    if (_disposed) return;
    final related = _routes.length > 1;
    if (_related == related) return;
    _related = related;
    onRelatedChanged(related);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _publish();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _scheduledPops.remove(route);
    _requestedPops.remove(route);
    _publish();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _scheduledPops.remove(route);
    _requestedPops.remove(route);
    _publish();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
    _scheduledPops.remove(oldRoute);
    _requestedPops.remove(oldRoute);
    _publish();
  }

  void pop(Route<dynamic> route, {bool afterFrame = false}) {
    if (_disposed ||
        !_routes.contains(route) ||
        !route.isCurrent ||
        route.isFirst ||
        _requestedPops.contains(route)) {
      return;
    }
    if (afterFrame) {
      if (!_scheduledPops.add(route)) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scheduledPops.remove(route)) return;
        pop(route);
      });
      // addPostFrameCallback alone does not request a frame when rendering is idle.
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    _scheduledPops.remove(route);
    _requestedPops.add(route);
    navigator?.pop();
  }

  void dispose() {
    _disposed = true;
    _scheduledPops.clear();
    _requestedPops.clear();
    _routes.clear();
    // The replacement pane establishes its own initial state. Never send a
    // late false notification into another pane from dispose/pop completion.
  }
}
