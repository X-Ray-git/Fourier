import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Short, opt-in trace of a local undo. Never logs article content or IDs.
class ReviewRestoreProbe {
  static bool get enabled =>
      !kReleaseMode &&
      const bool.fromEnvironment('FOURIER_REVIEW_RESTORE_PROBE') &&
      Platform.isMacOS;
  final _clock = Stopwatch();
  int _sequence = 0;
  String? _id;
  Timer? _timer;
  int _frames = 0;
  double? _firstVisible;
  double? _last;
  int _lastFrameUs = 0;
  int _maxGapUs = 0;
  bool _built = false;

  void begin(String id, int sequence) {
    _timer?.cancel();
    _id = id;
    _sequence = sequence;
    _clock
      ..reset()
      ..start();
    _built = false;
    _frames = _lastFrameUs = _maxGapUs = 0;
    _firstVisible = _last = null;
    mark(id, 'prepare utcUs=${DateTime.now().toUtc().microsecondsSinceEpoch}');
    _timer = Timer(const Duration(milliseconds: 1000), () {
      mark(
        id,
        'end sampledFrames=$_frames firstVisible=$_firstVisible last=$_last maxGapUs=$_maxGapUs',
      );
      _id = null;
      _animation = null;
    });
  }

  void mark(String id, String message) {
    if (_id != id) return;
    debugPrintSynchronously(
      '[ReviewRestore] seq=$_sequence us=${_clock.elapsedMicroseconds} $message',
    );
  }

  void built(
    String id,
    int index,
    Animation<double> animation,
    BuildContext? Function() rowContext,
  ) {
    if (_id != id) return;
    // AnimatedList may rebuild with a different Animation object. Keep the
    // current one for subsequent samples without scheduling a second sampler.
    _animation = animation;
    if (_built) return;
    _built = true;
    mark(id, 'firstBuild index=$index value=${animation.value}');
    final sequence = _sequence;
    void sample(Duration _) {
      if (_id != id || sequence != _sequence) return;
      final context = rowContext();
      final row = context?.findRenderObject();
      if (row is RenderBox && row.attached && row.hasSize) {
        final RenderObject? viewport = RenderAbstractViewport.maybeOf(row);
        if (viewport is RenderBox && viewport.hasSize) {
          final rect = MatrixUtils.transformRect(
            row.getTransformTo(viewport),
            row.paintBounds,
          );
          final visible = rect.overlaps(viewport.paintBounds);
          final value = _animation!.value;
          final now = _clock.elapsedMicroseconds;
          if (_frames > 0 && now - _lastFrameUs > _maxGapUs) {
            _maxGapUs = now - _lastFrameUs;
          }
          _lastFrameUs = now;
          _frames++;
          _last = value;
          if (_frames == 1 || (_firstVisible == null && visible && value > 0)) {
            mark(
              id,
              'layout value=$value overlaps=$visible top=${rect.top.round()} px=${Scrollable.maybeOf(context!)?.position.pixels.round()}',
            );
          }
          if (visible && value > 0) _firstVisible ??= value;
          if (value >= 1 && _firstVisible != null) return;
        }
      }
      // Observe natural frames only; instrumentation must not drive animation.
      WidgetsBinding.instance.addPostFrameCallback(sample);
    }

    WidgetsBinding.instance.addPostFrameCallback(sample);
  }

  Animation<double>? _animation;

  void dispose() {
    _timer?.cancel();
    _id = null;
    _animation = null;
  }
}
