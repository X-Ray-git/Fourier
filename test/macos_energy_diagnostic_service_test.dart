import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/services/macos_energy_diagnostic_service.dart';

void main() {
  test('calculates process CPU from cumulative CPU time', () {
    final start = DateTime(2026, 1, 1);
    expect(
      calculateProcessCpuPercent(
        previousCpuSeconds: 10,
        previousAt: start,
        cpuSeconds: 12,
        sampledAt: start.add(const Duration(seconds: 10)),
      ),
      closeTo(20, 0.001),
    );
  });

  test('writes active samples and sparse idle heartbeats', () {
    expect(
      shouldWriteEnergySample(
        cpuPercent: 0.1,
        frameCount: 0,
        queuedOrRunningTasks: 0,
        syncing: false,
        sinceLastWrite: const Duration(minutes: 1),
      ),
      isFalse,
    );
    expect(
      shouldWriteEnergySample(
        cpuPercent: 0.1,
        frameCount: 0,
        queuedOrRunningTasks: 0,
        syncing: false,
        sinceLastWrite: const Duration(minutes: 5),
      ),
      isTrue,
    );
    expect(
      shouldWriteEnergySample(
        cpuPercent: 0.1,
        frameCount: 1,
        queuedOrRunningTasks: 0,
        syncing: false,
        sinceLastWrite: Duration.zero,
      ),
      isTrue,
    );
  });
}
