import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show ErrorWidget;
import 'package:path_provider/path_provider.dart';

import 'ui_incident_trace.dart';

enum UiDiagnosticAction {
  refreshStart,
  refreshEnd,
  undoRequested,
  redoRequested,
  sectionChanged,
  articleMounted,
  articleDisposed,
}

/// Local, bounded diagnostics. Never records article text, URLs or exception
/// messages: stack locations and overlay identities are sufficient to locate
/// failing builders without copying user content into the log.
abstract final class UiDiagnosticService {
  static UiDiagnosticWriter? _writer;
  static UiDiagnosticWriter? _incidentWriter;
  static final _trace = UiIncidentTrace();
  static bool _installed = false;
  static int _nextOverlay = 0;
  static int _nextRequest = 0;

  static Future<void> initialize() async {
    if (_installed) return;
    _installed = true;
    final previousFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      _recordError(
        uiErrorDiagnosticFields(
          'flutter',
          details.exception,
          details.stack,
          library: details.library,
          context: details.context,
        ),
      );
      previousFlutter?.call(details);
    };
    final previousPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      recordError('platform', error, stack);
      // Preserve whether the existing handler considers the error handled.
      return previousPlatform?.call(error, stack) ?? false;
    };
    final previousErrorWidget = ErrorWidget.builder;
    ErrorWidget.builder = (details) {
      final fields = uiErrorDiagnosticFields(
        'flutter',
        details.exception,
        details.stack,
        library: details.library,
        context: details.context,
      );
      fields.remove('stack');
      _recordError({...fields, 'event': 'error_widget'});
      return previousErrorWidget(details);
    };
    try {
      final support = await getApplicationSupportDirectory();
      _writer = UiDiagnosticWriter(
        File('${support.path}/diagnostics/ui.jsonl'),
      );
      _incidentWriter = UiDiagnosticWriter(
        File('${support.path}/diagnostics/ui-incidents.jsonl'),
        maxBytes: 256 * 1024,
      );
      _writer!.record({'event': 'session_start'});
    } catch (_) {
      // Diagnostic storage must never prevent application startup.
    }
  }

  /// Opt-in timings contain no article identifiers or content. Enable in profile
  /// or release builds with --dart-define=FOURIER_READER_PERF=true.
  static void recordReaderTiming(String phase, int microseconds) {
    if (!const bool.fromEnvironment('FOURIER_READER_PERF')) return;
    _writer?.record({
      'event': 'reader_timing',
      'phase': phase,
      'us': microseconds,
    });
  }

  static void action(UiDiagnosticAction action, {int? section}) {
    _trace.record({
      'event': 'action',
      'action': action.name,
      'section': ?section,
    });
  }

  static int feedbackRequested() {
    final id = ++_nextRequest;
    final caller = StackTrace.current
        .toString()
        .split('\n')
        .where(
          (line) =>
              line.contains('package:fourier/') &&
              !line.contains('/ui_diagnostic_service.dart:') &&
              !line.contains('/feedback_toast.dart:'),
        )
        .take(3)
        .toList();
    _event({'event': 'feedback_request', 'requestId': id, 'caller': caller});
    return id;
  }

  static void feedbackPhase(int requestId, String phase) {
    _event({'event': 'feedback_phase', 'requestId': requestId, 'phase': phase});
  }

  static void _event(Map<String, Object?> fields) {
    _trace.record(fields);
    _writer?.record(fields);
  }

  static int overlayOpened(
    String kind, {
    int? requestId,
    String? component,
    List<Map<String, Object?>>? ancestors,
  }) {
    final id = ++_nextOverlay;
    final fields = {
      'kind': kind,
      'requestId': ?requestId,
      'component': ?component,
      'ancestors': ?ancestors,
    };
    _trace.opened(id, fields);
    _event({'event': 'overlay_open', ...fields, 'id': id});
    return id;
  }

  static void overlayClosed(String kind, int? id) {
    if (id == null) return;
    _trace.closed(id);
    _event({'event': 'overlay_close', 'kind': kind, 'id': id});
  }

  static void recordError(String source, Object error, StackTrace? stack) {
    _recordError(uiErrorDiagnosticFields(source, error, stack));
  }

  static void _recordError(Map<String, Object?> fields) {
    final stack = fields['stack'] as List<String>?;
    final signature =
        '${fields['event']}/${fields['library']}/${fields['type']}/${stack?.firstOrNull}';
    final prelude = _trace.incident(signature);
    if (prelude != null) {
      _incidentWriter?.record({
        'event': 'ui_incident',
        'error': fields,
        ...prelude,
      });
    }
    _writer?.record(fields);
  }

  @visibleForTesting
  static Future<void> flushForTesting() async {
    await _writer?.flush();
    await _incidentWriter?.flush();
  }
}

/// Keep only framework phase/type identifiers, never the context description.
/// Flutter's description can include Text contents, keys, URLs or credentials.
@visibleForTesting
Map<String, Object?> uiErrorDiagnosticFields(
  String source,
  Object error,
  StackTrace? stack, {
  String? library,
  DiagnosticsNode? context,
}) {
  const libraries = {
    'widgets library',
    'rendering library',
    'scheduler library',
    'gestures library',
    'painting library',
    'services library',
    'animation library',
    'image resource service',
  };
  String? widgetType;
  String? elementType;
  try {
    if (library == 'widgets library') {
      final description = context?.toDescription() ?? '';
      elementType = RegExp(
        r"^building Instance of '([A-Za-z_][A-Za-z0-9_]*Element)'$",
      ).firstMatch(description)?.group(1);
      widgetType = RegExp(
        r'^building ([A-Za-z_][A-Za-z0-9_]*)(?=[#(\[<\-\s]|$)',
      ).firstMatch(description)?.group(1);
      if (widgetType == 'Instance') widgetType = null;
    }
  } catch (_) {
    // An invalid diagnostic node must not prevent the original error handler.
  }
  return {
    'event': 'error',
    'source': source,
    'type': error.runtimeType.toString(),
    if (libraries.contains(library)) 'library': library,
    'widgetType': ?widgetType,
    'elementType': ?elementType,
    'stack': (stack ?? StackTrace.current)
        .toString()
        .split('\n')
        .where(
          (line) =>
              line.startsWith('#') &&
              (line.contains('package:') || line.contains('dart:')),
        )
        .take(40)
        .toList(),
  };
}

/// Serial writes and bounded pending work prevent error storms from creating
/// concurrent file rotations or an unbounded diagnostic queue.
class UiDiagnosticWriter {
  UiDiagnosticWriter(this.file, {this.maxBytes = 512 * 1024});

  final File file;
  final int maxBytes;
  Future<void> _tail = Future.value();
  int _pending = 0;

  void record(Map<String, Object?> fields) {
    if (_pending >= 64) return;
    final line =
        '${jsonEncode({'at': DateTime.now().toUtc().toIso8601String(), 'pid': pid, ...fields})}\n';
    _pending++;
    _tail = _tail.then((_) async {
      try {
        await file.parent.create(recursive: true);
        if (await file.exists() && await file.length() >= maxBytes) {
          final previous = File('${file.path}.previous');
          if (await previous.exists()) await previous.delete();
          await file.rename(previous.path);
        }
        await file.writeAsString(line, mode: FileMode.append, flush: true);
      } catch (_) {
        // Never report logging failures through FlutterError (recursive).
      } finally {
        _pending--;
      }
    });
  }

  Future<void> flush() => _tail;
}
