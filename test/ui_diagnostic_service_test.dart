import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/services/ui_diagnostic_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('fourier-ui-log-'),
  );
  tearDown(() async => directory.delete(recursive: true));

  test('serial events remain ordered with bounded pending work', () async {
    final file = File('${directory.path}/ui.jsonl');
    final writer = UiDiagnosticWriter(file);
    for (var i = 0; i < 100; i++) {
      writer.record({'event': 'test', 'id': i});
    }
    await writer.flush();
    final rows = (await file.readAsLines())
        .map((s) => jsonDecode(s) as Map)
        .toList();
    expect(rows.length, 64);
    expect(
      rows.map((r) => r['id']),
      orderedEquals(List.generate(64, (i) => i)),
    );
    writer.record({'event': 'recovered'});
    await writer.flush();
    expect((await file.readAsLines()).length, 65);
  });

  test(
    'rotation retains one previous file and does not lose the new event',
    () async {
      final file = File('${directory.path}/ui.jsonl');
      final writer = UiDiagnosticWriter(file, maxBytes: 1);
      for (var i = 0; i < 3; i++) {
        writer.record({'id': i});
        await writer.flush();
      }
      expect(jsonDecode(await file.readAsString())['id'], 2);
      expect(
        jsonDecode(await File('${file.path}.previous').readAsString())['id'],
        1,
      );
    },
  );

  test('storage failure is swallowed and later events can recover', () async {
    final blocker = File('${directory.path}/blocked');
    await blocker.writeAsString('not a directory');
    final file = File('${blocker.path}/ui.jsonl');
    final writer = UiDiagnosticWriter(file);
    writer.record({'event': 'failed'});
    await writer.flush();
    await blocker.delete();
    writer.record({'event': 'recovered'});
    await writer.flush();
    expect(jsonDecode(await file.readAsString())['event'], 'recovered');
  });

  test(
    'widget context keeps only type identifiers and never message contents',
    () {
      final fields = uiErrorDiagnosticFields(
        'flutter',
        StateError('PRIVATE_EXCEPTION_CONTENT'),
        StackTrace.fromString(
          '#0 build (package:fourier/example.dart:1)\nPRIVATE_STACK_CONTENT',
        ),
        library: 'widgets library',
        context: ErrorDescription(
          'building Text("PRIVATE_ARTICLE_CONTENT", key: [PRIVATE_KEY], url: https://private.example/path)',
        ),
      );
      expect(fields['widgetType'], 'Text');
      expect(fields['library'], 'widgets library');
      expect(fields['stack'], ['#0 build (package:fourier/example.dart:1)']);
      expect(jsonEncode(fields), isNot(contains('PRIVATE_')));
      expect(jsonEncode(fields), isNot(contains('private.example')));
    },
  );

  test('overlay and generic widget names exclude keys and type arguments', () {
    for (final entry in {
      'building _OverlayEntryWidget-[LabeledGlobalKey<State>#private]':
          '_OverlayEntryWidget',
      'building Obx(dirty, state: private)': 'Obx',
      'building Builder<PrivateType>#private': 'Builder',
    }.entries) {
      final fields = uiErrorDiagnosticFields(
        'flutter',
        StateError('failure'),
        null,
        library: 'widgets library',
        context: ErrorDescription(entry.key),
      );
      expect(fields['widgetType'], entry.value);
      expect(jsonEncode(fields), isNot(contains('private')));
      expect(jsonEncode(fields), isNot(contains('PrivateType')));
    }
  });

  test('unknown libraries and non-build descriptions are not recorded', () {
    final fields = uiErrorDiagnosticFields(
      'flutter',
      StateError('failure'),
      null,
      library: 'PRIVATE_LIBRARY',
      context: ErrorDescription('PRIVATE_CONTEXT'),
    );
    expect(fields.containsKey('library'), false);
    expect(fields.containsKey('widgetType'), false);
    expect(jsonEncode(fields), isNot(contains('PRIVATE_')));
  });

  test(
    'installed hooks preserve original handlers and error widget appearance',
    () async {
      final previousProvider = PathProviderPlatform.instance;
      final previousFlutter = FlutterError.onError;
      final previousPlatform = PlatformDispatcher.instance.onError;
      final previousBuilder = ErrorWidget.builder;
      var flutterCalls = 0;
      var platformCalls = 0;
      var builderCalls = 0;
      var handled = false;
      const fallback = SizedBox(width: 17, height: 19);
      PathProviderPlatform.instance = _DiagnosticPathProvider(directory.path);
      FlutterError.onError = (_) => flutterCalls++;
      PlatformDispatcher.instance.onError = (_, _) {
        platformCalls++;
        return handled;
      };
      ErrorWidget.builder = (_) {
        builderCalls++;
        return fallback;
      };
      try {
        await UiDiagnosticService.initialize();
        final details = FlutterErrorDetails(
          exception: StateError('PRIVATE_MESSAGE'),
          library: 'widgets library',
          context: ErrorDescription('building Builder(dirty)'),
        );
        FlutterError.onError!(details);
        expect(flutterCalls, 1);
        expect(ErrorWidget.builder(details), same(fallback));
        expect(builderCalls, 1);
        expect(
          PlatformDispatcher.instance.onError!(
            StateError('PRIVATE_MESSAGE'),
            StackTrace.current,
          ),
          false,
        );
        handled = true;
        expect(
          PlatformDispatcher.instance.onError!(
            StateError('PRIVATE_MESSAGE'),
            StackTrace.current,
          ),
          true,
        );
        expect(platformCalls, 2);
        await UiDiagnosticService.flushForTesting();
        final text = await File('${directory.path}/diagnostics/ui.jsonl')
            .readAsString();
        final rows = text
            .split('\n')
            .where((line) => line.isNotEmpty)
            .map((line) => jsonDecode(line) as Map)
            .toList();
        expect(
          rows
              .where((row) => row['event'] == 'error_widget')
              .single['widgetType'],
          'Builder',
        );
        expect(rows.where((row) => row['event'] == 'error').length, 3);
        expect(text, isNot(contains('PRIVATE_MESSAGE')));
      } finally {
        FlutterError.onError = previousFlutter;
        PlatformDispatcher.instance.onError = previousPlatform;
        ErrorWidget.builder = previousBuilder;
        PathProviderPlatform.instance = previousProvider;
      }
    },
  );
}

class _DiagnosticPathProvider extends PathProviderPlatform {
  _DiagnosticPathProvider(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}
