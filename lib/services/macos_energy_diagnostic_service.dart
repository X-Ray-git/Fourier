import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import '../pages/main/main_controller.dart';
import '../pages/timeline/timeline_controller.dart';
import 'article_image_cache_service.dart';
import 'animated_image_playback_monitor.dart';
import 'article_relation_service.dart';
import 'article_relation_worker.dart';
import 'auto_filter_worker.dart';
import 'auto_readability_worker.dart';
import 'auto_summary_worker.dart';
import 'auto_translation_worker.dart';

@visibleForTesting
double? calculateProcessCpuPercent({
  required double? previousCpuSeconds,
  required DateTime? previousAt,
  required double cpuSeconds,
  required DateTime sampledAt,
}) {
  if (previousCpuSeconds == null || previousAt == null) return null;
  final wallSeconds = sampledAt.difference(previousAt).inMicroseconds / 1e6;
  if (wallSeconds <= 0) return null;
  return ((cpuSeconds - previousCpuSeconds) / wallSeconds * 100).clamp(
    0,
    double.infinity,
  );
}

@visibleForTesting
bool shouldWriteEnergySample({
  required double cpuPercent,
  required int frameCount,
  required int queuedOrRunningTasks,
  required bool syncing,
  required Duration sinceLastWrite,
}) {
  return cpuPercent >= 1 ||
      frameCount > 0 ||
      queuedOrRunningTasks > 0 ||
      syncing ||
      sinceLastWrite >= const Duration(minutes: 5);
}

/// Low-overhead, content-free diagnostics for intermittent macOS energy use.
///
/// Samples stay on the local device and never include article text, URLs,
/// prompts, account identifiers, or credentials.
abstract final class MacosEnergyDiagnosticService {
  static const _channel = MethodChannel(
    'io.github.xraygit.fourier/energy_diagnostics',
  );
  static const _sampleInterval = Duration(seconds: 15);
  static const _maxLogBytes = 2 * 1024 * 1024;

  static Timer? _timer;
  static File? _logFile;
  static bool _sampling = false;
  static double? _previousCpuSeconds;
  static DateTime? _previousSampleAt;
  static DateTime? _lastWriteAt;
  static int _frameCount = 0;
  static int _slowFrameCount = 0;
  static int _maxBuildMicros = 0;
  static int _maxRasterMicros = 0;

  static Future<void> initialize() async {
    if (!Platform.isMacOS || _timer != null) return;
    try {
      final support = await getApplicationSupportDirectory();
      final directory = Directory('${support.path}/diagnostics');
      await directory.create(recursive: true);
      _logFile = File('${directory.path}/energy.jsonl');
      SchedulerBinding.instance.addTimingsCallback(_recordFrameTimings);
      await _sample();
      _timer = Timer.periodic(_sampleInterval, (_) => unawaited(_sample()));
    } catch (error) {
      debugPrint('Energy diagnostics initialization failed: $error');
    }
  }

  static void _recordFrameTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _frameCount++;
      final build = timing.buildDuration.inMicroseconds;
      final raster = timing.rasterDuration.inMicroseconds;
      if (build + raster > 16667) _slowFrameCount++;
      if (build > _maxBuildMicros) _maxBuildMicros = build;
      if (raster > _maxRasterMicros) _maxRasterMicros = raster;
    }
  }

  static Future<void> _sample() async {
    if (_sampling || _logFile == null) return;
    _sampling = true;
    try {
      final now = DateTime.now();
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'getProcessMetrics',
      );
      if (raw == null) return;

      final cpuSeconds = (raw['cpuSeconds'] as num?)?.toDouble() ?? 0;
      final cpuPercent =
          calculateProcessCpuPercent(
            previousCpuSeconds: _previousCpuSeconds,
            previousAt: _previousSampleAt,
            cpuSeconds: cpuSeconds,
            sampledAt: now,
          ) ??
          0;
      _previousCpuSeconds = cpuSeconds;
      _previousSampleAt = now;

      final image = ArticleImageCacheService.diagnosticSnapshot;
      final animatedImages = AnimatedImagePlaybackMonitor.takeSnapshot();
      final syncing = Get.isRegistered<TimelineController>()
          ? Get.find<TimelineController>().isSyncing.value
          : false;
      final taskCounts = <String, int>{
        'imageForegroundQueued': image['foregroundQueued'] ?? 0,
        'imageBackgroundQueued': image['backgroundQueued'] ?? 0,
        'imageRunning': image['running'] ?? 0,
        'imageFailedArticles': image['failedArticles'] ?? 0,
        'readabilityQueued': AutoReadabilityWorker.queueSize,
        'readabilityRunning': AutoReadabilityWorker.runningCount,
        'readabilityRetrying': AutoReadabilityWorker.retryCount,
        'translationQueued': AutoTranslationWorker.queueSize,
        'translationRunning': AutoTranslationWorker.runningCount,
        'summaryQueued': AutoSummaryWorker.queueSize,
        'summaryRunning': AutoSummaryWorker.runningCount,
        'filterQueued': AutoFilterWorker.queueSize,
        'filterRunning': AutoFilterWorker.runningCount,
        'relationPending': ArticleRelationService.pendingCount,
        'relationRunning': ArticleRelationWorker.processingCount.value,
      };
      final queuedOrRunning = taskCounts.entries
          .where((entry) => !entry.key.endsWith('FailedArticles'))
          .fold<int>(0, (sum, entry) => sum + entry.value);
      final frameCount = _frameCount;
      final sinceLastWrite = _lastWriteAt == null
          ? const Duration(days: 1)
          : now.difference(_lastWriteAt!);
      if (!shouldWriteEnergySample(
        cpuPercent: cpuPercent,
        frameCount: frameCount,
        queuedOrRunningTasks: queuedOrRunning,
        syncing: syncing,
        sinceLastWrite: sinceLastWrite,
      )) {
        _resetFrameBucket();
        return;
      }

      final section = Get.isRegistered<MainController>()
          ? Get.find<MainController>().currentIndex.value
          : null;
      final record = <String, Object?>{
        'schema': 2,
        'at': now.toUtc().toIso8601String(),
        'process': {
          'cpuPercent': double.parse(cpuPercent.toStringAsFixed(2)),
          'residentBytes': raw['residentBytes'],
          'lowPowerMode': raw['lowPowerMode'],
          'thermalState': raw['thermalState'],
        },
        'app': {
          'active': raw['appActive'],
          'windowVisible': raw['windowVisible'],
          'windowMiniaturized': raw['windowMiniaturized'],
          'sectionIndex': section,
          'timelineSyncing': syncing,
        },
        'frames': {
          'count': frameCount,
          'slow': _slowFrameCount,
          'maxBuildMs': _maxBuildMicros / 1000,
          'maxRasterMs': _maxRasterMicros / 1000,
        },
        'tasks': taskCounts,
        'animatedImages': animatedImages,
      };
      await _rotateIfNeeded();
      await _logFile!.writeAsString(
        '${jsonEncode(record)}\n',
        mode: FileMode.append,
        flush: false,
      );
      _lastWriteAt = now;
      _resetFrameBucket();
    } catch (error) {
      debugPrint('Energy diagnostics sample failed: $error');
    } finally {
      _sampling = false;
    }
  }

  static Future<void> _rotateIfNeeded() async {
    final file = _logFile!;
    if (!await file.exists() || await file.length() < _maxLogBytes) return;
    final previous = File('${file.path}.previous');
    if (await previous.exists()) await previous.delete();
    await file.rename(previous.path);
    _logFile = File(file.path);
  }

  static void _resetFrameBucket() {
    _frameCount = 0;
    _slowFrameCount = 0;
    _maxBuildMicros = 0;
    _maxRasterMicros = 0;
  }
}
