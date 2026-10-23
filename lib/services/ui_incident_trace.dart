import 'dart:collection';

/// Small in-memory prelude, independent of debug-only Flutter descriptions.
/// Callers supply only code identities, numeric counters and fixed action names.
class UiIncidentTrace {
  UiIncidentTrace({this.capacity = 64, this.activeLimit = 32});

  final int capacity;
  final int activeLimit;
  final Queue<Map<String, Object?>> _events = Queue();
  final Map<int, Map<String, Object?>> _active = {};
  final Map<String, DateTime> _lastIncident = {};
  int _sequence = 0;

  void record(Map<String, Object?> fields, {DateTime? at}) {
    _events.add({
      'sequence': ++_sequence,
      'at': (at ?? DateTime.now()).toUtc().toIso8601String(),
      ...fields,
    });
    while (_events.length > capacity) {
      _events.removeFirst();
    }
  }

  void opened(int id, Map<String, Object?> fields) {
    _active[id] = {'id': id, ...fields};
    while (_active.length > activeLimit) {
      _active.remove(_active.keys.first);
    }
  }

  void closed(int id) => _active.remove(id);

  /// Each distinct error phase gets its own prelude. Repeated error storms are
  /// sampled at most once per minute per signature, without hiding later phases.
  Map<String, Object?>? incident(String signature, {DateTime? at}) {
    final now = at ?? DateTime.now();
    final previous = _lastIncident[signature];
    if (previous != null &&
        now.difference(previous) < const Duration(minutes: 1)) {
      return null;
    }
    _lastIncident.remove(signature);
    _lastIncident[signature] = now;
    while (_lastIncident.length > 16) {
      _lastIncident.remove(_lastIncident.keys.first);
    }
    return {
      'recent': _events.toList(growable: false),
      'activeOverlays': _active.values.toList(growable: false),
    };
  }
}
