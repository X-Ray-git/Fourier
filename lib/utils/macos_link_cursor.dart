import 'dart:async';

import 'package:flutter/services.dart';

import '../services/ui_diagnostic_service.dart';

/// Uses Flutter's standard cursor channel, then observes AppKit.
/// No cursor resets, polling loop, URLs or article identifiers are involved.
class MacOSLinkCursor extends MouseCursor {
  const MacOSLinkCursor();

  static const instance = MacOSLinkCursor();
  static final diagnostics = CursorDiagnosticSampler();

  @override
  MouseCursorSession createSession(int device) =>
      _LinkCursorSession(this, device);

  @override
  String get debugDescription => 'macOS link (diagnostic)';
}

class _LinkCursorSession extends MouseCursorSession {
  _LinkCursorSession(super.cursor, super.device);
  bool _disposed = false;
  void Function()? _cancel;

  @override
  Future<void> activate() async {
    await SystemChannels.mouseCursor.invokeMethod<void>(
      'activateSystemCursor',
      {'device': device, 'kind': 'click'},
    );
    if (!_disposed) _cancel = MacOSLinkCursor.diagnostics.begin(device);
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel?.call();
  }
}

/// At most three observations per activation, and one probe per two seconds.
/// Injectable boundaries allow lifecycle/rate-limit tests without native UI.
class CursorDiagnosticSampler {
  CursorDiagnosticSampler({
    Future<Map<Object?, Object?>?> Function()? readNative,
    void Function(Map<String, Object?>)? record,
    DateTime Function()? now,
  }) : _readNative = readNative ?? _readSnapshot,
       _record = record ?? UiDiagnosticService.recordCursorDiagnostic,
       _now = now ?? DateTime.now;

  static const _channel = MethodChannel('io.github.xraygit.fourier/cursor');
  static Future<Map<Object?, Object?>?> _readSnapshot() =>
      _channel.invokeMapMethod<Object?, Object?>('getCursorDiagnostics');

  final Future<Map<Object?, Object?>?> Function() _readNative;
  final void Function(Map<String, Object?>) _record;
  final DateTime Function() _now;
  DateTime? _lastProbe;
  int _sequence = 0;

  void Function() begin(int device) {
    final now = _now();
    if (_lastProbe != null &&
        now.difference(_lastProbe!) < const Duration(seconds: 2)) {
      return () {};
    }
    _lastProbe = now;
    final id = ++_sequence;
    var active = true;
    final timers = <Timer>[];
    _record({
      'event': 'cursor_probe_start',
      'probe': id,
      'device': device,
      'requested': 'click',
      'activationAcknowledged': true,
    });
    Future<void> sample(int delayMs) async {
      try {
        final snapshot = await _readNative();
        if (!active) return;
        _record({
          'event': 'cursor_probe_sample',
          'probe': id,
          'delayMs': delayMs,
          // Native schema contains only cursor/view type names and booleans.
          'native': {
            for (final key in const [
              'appActive',
              'windowKey',
              'windowVisible',
              'mouseInside',
              'current',
              'system',
              'hitView',
              'hitAncestors',
              'firstResponder',
            ])
              if (snapshot?.containsKey(key) ?? false) key: snapshot![key],
          },
        });
      } catch (error) {
        if (active) {
          _record({
            'event': 'cursor_probe_unavailable',
            'probe': id,
            'delayMs': delayMs,
            'type': error.runtimeType.toString(),
          });
        }
      }
    }

    unawaited(sample(0));
    for (final delay in [180, 600]) {
      timers.add(Timer(Duration(milliseconds: delay), () => sample(delay)));
    }
    return () {
      if (!active) return;
      active = false;
      for (final timer in timers) {
        timer.cancel();
      }
      _record({'event': 'cursor_probe_end', 'probe': id});
    };
  }
}
