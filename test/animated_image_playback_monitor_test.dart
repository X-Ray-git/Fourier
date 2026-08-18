import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/services/animated_image_playback_monitor.dart';

void main() {
  setUp(AnimatedImagePlaybackMonitor.resetForTesting);
  tearDown(AnimatedImagePlaybackMonitor.resetForTesting);

  test('reports anonymous playback state and resets interval counters', () {
    final playing = Object();
    final inactive = Object();
    AnimatedImagePlaybackMonitor.register(playing);
    AnimatedImagePlaybackMonitor.register(inactive);
    AnimatedImagePlaybackMonitor.update(
      playing,
      windowActive: true,
      nearViewport: true,
      playing: true,
      hasFrame: true,
    );
    AnimatedImagePlaybackMonitor.update(
      inactive,
      windowActive: false,
      nearViewport: true,
      playing: false,
      hasFrame: true,
    );
    AnimatedImagePlaybackMonitor.recordFrameCallback();
    AnimatedImagePlaybackMonitor.recordStreamResolve();

    expect(AnimatedImagePlaybackMonitor.takeSnapshot(), {
      'registered': 2,
      'nearViewport': 2,
      'playing': 1,
      'frozenOffscreen': 0,
      'frozenInactive': 1,
      'waitingForFirstFrame': 0,
      'frameCallbacks': 1,
      'streamResolves': 1,
      'stateChanges': 2,
    });

    final next = AnimatedImagePlaybackMonitor.takeSnapshot();
    expect(next['registered'], 2);
    expect(next['frameCallbacks'], 0);
    expect(next['streamResolves'], 0);
    expect(next['stateChanges'], 0);
  });
}
