import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
      recordError('flutter', details.exception, details.stack);
      previousFlutter?.call(details);
    };
    final previousPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      recordError('platform', error, stack);
      // Preserve whether the existing handler considers the error handled.
      return previousPlatform?.call(error, stack) ?? false;
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
    _writer?.record({
      'event': 'error',
      'source': source,
      'type': error.runtimeType.toString(),
      // Keep only Dart stack frames; omit absolute paths and arbitrary lines.
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
    });
  }
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
