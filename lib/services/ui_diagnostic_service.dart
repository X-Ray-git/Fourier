import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show ErrorWidget;
import 'package:path_provider/path_provider.dart';

/// Local, bounded diagnostics. Never records article text, URLs or exception
/// messages: stack locations and overlay identities are sufficient to locate
/// failing builders without copying user content into the log.
abstract final class UiDiagnosticService {
  static UiDiagnosticWriter? _writer;
  static bool _installed = false;
  static int _nextOverlay = 0;

  static Future<void> initialize() async {
    if (_installed) return;
    _installed = true;
    final previousFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      _writer?.record(
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
      _writer?.record({...fields, 'event': 'error_widget'});
      return previousErrorWidget(details);
    };
    try {
      final support = await getApplicationSupportDirectory();
      _writer = UiDiagnosticWriter(
        File('${support.path}/diagnostics/ui.jsonl'),
      );
      _writer!.record({'event': 'session_start'});
    } catch (_) {
      // Diagnostic storage must never prevent application startup.
    }
  }

  static int overlayOpened(String kind) {
    final id = ++_nextOverlay;
    _writer?.record({'event': 'overlay_open', 'kind': kind, 'id': id});
    return id;
  }

  static void overlayClosed(String kind, int? id) {
    if (id == null) return;
    _writer?.record({'event': 'overlay_close', 'kind': kind, 'id': id});
  }

  static void recordError(String source, Object error, StackTrace? stack) {
    _writer?.record(uiErrorDiagnosticFields(source, error, stack));
  }

  @visibleForTesting
  static Future<void> flushForTesting() async => _writer?.flush();
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
  try {
    if (library == 'widgets library') {
      widgetType = RegExp(
        r'^building ([A-Za-z_][A-Za-z0-9_]*)(?=[#(\[<\-\s]|$)',
      ).firstMatch(context?.toDescription() ?? '')?.group(1);
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
